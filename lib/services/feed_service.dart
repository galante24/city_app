import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_ready.dart';
import '../models/news_feed_category.dart';
import '../utils/feed_image_compress.dart';
import 'city_data_service.dart';

/// Права публикации в ленте (зеркало RLS).
class FeedAccess {
  const FeedAccess({required this.isProfilesAdmin, required this.feedRole});

  final bool isProfilesAdmin;

  /// `user` | `moderator_news` | `moderator_important` (admin через [isProfilesAdmin]).
  final String feedRole;

  bool get isFullAdmin => isProfilesAdmin;

  String get effectiveRole => isFullAdmin ? 'admin' : feedRole;

  bool canPublishIn(NewsCategory category) {
    if (isFullAdmin) {
      return true;
    }
    switch (category) {
      case NewsCategory.smi:
        return feedRole == 'moderator_news';
      case NewsCategory.administration:
        return feedRole == 'moderator_important';
      case NewsCategory.discussion:
        return feedRole == 'user' ||
            feedRole == 'moderator_news' ||
            feedRole == 'moderator_important';
    }
  }

  bool get canCreateSomewhere =>
      isFullAdmin ||
      feedRole == 'moderator_news' ||
      feedRole == 'moderator_important' ||
      feedRole == 'user';

  /// Удаление поста (RLS): модератор своей вкладки, автор — только «Обсуждение», admin — всё.
  bool canDeletePostDb({
    required String postUserId,
    required String categoryDb,
    required String? myUserId,
  }) {
    if (isFullAdmin) {
      return true;
    }
    if (effectiveRole == 'moderator_news' && categoryDb == 'smi') {
      return true;
    }
    if (effectiveRole == 'moderator_important' &&
        categoryDb == 'administration') {
      return true;
    }
    return myUserId != null &&
        myUserId == postUserId &&
        categoryDb == 'discussion';
  }

  static FeedAccess fallbackUser() =>
      const FeedAccess(isProfilesAdmin: false, feedRole: 'user');
}

/// API социальной ленты (таблицы `posts`, `feed_comments`, `feed_likes`, `notifications`).
class FeedService {
  FeedService(this._client);

  final SupabaseClient _client;

  static const int pageSize = 3;

  static const String _postSelect = '''
id, title, content, category, image_urls, created_at, updated_at, user_id,
likes_count, comments_count,
author:profiles!posts_user_id_fkey(id, username, first_name, last_name, avatar_url)
''';

  static const String _commentSelect = '''
id, post_id, user_id, parent_id, body, image_urls, likes_count, created_at,
author:profiles!feed_comments_user_id_fkey(id, username, first_name, last_name, avatar_url)
''';

  static FeedService? tryOf(SupabaseClient? c) {
    if (c == null || !supabaseAppReady) {
      return null;
    }
    return FeedService(c);
  }

  Future<FeedAccess> loadMyAccess() async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return FeedAccess.fallbackUser();
    }
    final Map<String, dynamic>? row = await _client
        .from('profiles')
        .select('is_admin, feed_role')
        .eq('id', uid)
        .maybeSingle();
    if (row == null) {
      return FeedAccess.fallbackUser();
    }
    return FeedAccess(
      isProfilesAdmin: row['is_admin'] == true,
      feedRole: (row['feed_role'] as String?)?.trim().isNotEmpty == true
          ? row['feed_role'] as String
          : 'user',
    );
  }

  Future<Map<String, dynamic>?> fetchPostRow(String postId) async {
    return _client
        .from('posts')
        .select(_postSelect)
        .eq('id', postId.trim())
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> fetchPostsPage({
    required NewsCategory category,
    required int offset,
    int limit = pageSize,
  }) async {
    final String cat = categoryToDb(category);
    final List<dynamic> rows = await _client
        .from('posts')
        .select(_postSelect)
        .eq('category', cat)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Set<String>> fetchMyLikedPostIds(Iterable<String> postIds) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null || postIds.isEmpty) {
      return <String>{};
    }
    final List<String> ids = postIds.toList();
    final List<dynamic> rows = await _client
        .from('feed_likes')
        .select('target_id')
        .eq('user_id', uid)
        .eq('target_type', 'post')
        .inFilter('target_id', ids);
    return rows
        .map((dynamic e) => (e as Map)['target_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<Map<String, dynamic>> createPost({
    required NewsCategory category,
    required String title,
    required String description,
    required List<String> imagePublicUrls,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Нет сессии');
    }
    final String t = title.trim();
    final String d = description.trim();
    if (t.isEmpty) {
      throw ArgumentError('Заголовок обязателен');
    }
    if (imagePublicUrls.length > 10) {
      throw ArgumentError('Не более 10 фото');
    }
    final Map<String, dynamic> row = Map<String, dynamic>.from(
      await _client
          .from('posts')
          .insert(<String, dynamic>{
            'user_id': user.id,
            'title': t,
            'content': d,
            'category': categoryToDb(category),
            'image_urls': imagePublicUrls,
          })
          .select(_postSelect)
          .single(),
    );
    return row;
  }

  Future<void> updatePost({
    required String postId,
    required String title,
    required String description,
    required List<String> imagePublicUrls,
  }) async {
    if (imagePublicUrls.length > 10) {
      throw ArgumentError('Не более 10 фото');
    }
    await _client
        .from('posts')
        .update(<String, dynamic>{
          'title': title.trim(),
          'content': description.trim(),
          'image_urls': imagePublicUrls,
        })
        .eq('id', postId.trim());
  }

  Future<void> deletePost(String postId) async {
    await _client.from('posts').delete().eq('id', postId.trim());
  }

  Future<void> togglePostLike({
    required String postId,
    required bool currentlyLiked,
  }) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    if (currentlyLiked) {
      await _client
          .from('feed_likes')
          .delete()
          .eq('user_id', uid)
          .eq('target_type', 'post')
          .eq('target_id', postId);
    } else {
      await _client.from('feed_likes').insert(<String, dynamic>{
        'user_id': uid,
        'target_type': 'post',
        'target_id': postId,
      });
    }
  }

  Future<void> toggleCommentLike({
    required String commentId,
    required bool currentlyLiked,
  }) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    if (currentlyLiked) {
      await _client
          .from('feed_likes')
          .delete()
          .eq('user_id', uid)
          .eq('target_type', 'comment')
          .eq('target_id', commentId);
    } else {
      await _client.from('feed_likes').insert(<String, dynamic>{
        'user_id': uid,
        'target_type': 'comment',
        'target_id': commentId,
      });
    }
  }

  Future<List<Map<String, dynamic>>> fetchComments(String postId) async {
    final List<dynamic> rows = await _client
        .from('feed_comments')
        .select(_commentSelect)
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return rows
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Set<String>> fetchMyLikedCommentIds(
    Iterable<String> commentIds,
  ) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null || commentIds.isEmpty) {
      return <String>{};
    }
    final List<dynamic> rows = await _client
        .from('feed_likes')
        .select('target_id')
        .eq('user_id', uid)
        .eq('target_type', 'comment')
        .inFilter('target_id', commentIds.toList());
    return rows
        .map((dynamic e) => (e as Map)['target_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<void> addComment({
    required String postId,
    required String body,
    String? parentId,
    required List<String> imagePublicUrls,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Нет сессии');
    }
    if (imagePublicUrls.length > 3) {
      throw ArgumentError('Не более 3 фото в комментарии');
    }
    await _client.from('feed_comments').insert(<String, dynamic>{
      'post_id': postId,
      'user_id': user.id,
      if (parentId != null && parentId.trim().isNotEmpty)
        'parent_id': parentId.trim(),
      'body': body.trim(),
      'image_urls': imagePublicUrls,
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _client.from('feed_comments').delete().eq('id', commentId.trim());
  }

  /// Уведомление автору поста при репосте в чат.
  Future<void> notifyRepost({
    required String postAuthorId,
    required String postId,
    String? titleSnippet,
  }) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null || postAuthorId == uid) {
      return;
    }
    await _client.from('notifications').insert(<String, dynamic>{
      'recipient_id': postAuthorId,
      'actor_id': uid,
      'type': 'repost',
      'post_id': postId,
      'payload': <String, dynamic>{
        if (titleSnippet != null && titleSnippet.isNotEmpty)
          'title': titleSnippet,
      },
    });
  }

  /// Загрузка в `city_media/feed_media/<uid>/...`; возвращает публичный URL.
  Future<String> uploadFeedImage(XFile file) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Нет сессии');
    }
    final XFile prepared = await compressFeedImageIfSupported(file);
    final String ext = _extFromName(prepared.name);
    final String objectPath = 'feed_media/${user.id}/${const Uuid().v4()}.$ext';
    const Map<String, String> ct = <String, String>{
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
    };
    final String contentType = ct[ext] ?? 'image/jpeg';
    final bucket = _client.storage.from(CityDataService.cityMediaBucket);
    if (kIsWeb) {
      final Uint8List bytes = await prepared.readAsBytes();
      await bucket.uploadBinary(
        objectPath,
        bytes,
        fileOptions: FileOptions(upsert: false, contentType: contentType),
      );
    } else {
      await bucket.upload(
        objectPath,
        File(prepared.path),
        fileOptions: FileOptions(upsert: false, contentType: contentType),
      );
    }
    return bucket.getPublicUrl(objectPath);
  }

  static String _extFromName(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) {
      return 'jpg';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  /// Подписка на изменения ленты (debounce).
  Stream<void> feedInvalidateStream() {
    RealtimeChannel? ch;
    late final StreamController<void> streamCtl;
    streamCtl = StreamController<void>(
      onListen: () {
        Timer? debounce;
        void bump() {
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 350), () {
            if (!streamCtl.isClosed) {
              streamCtl.add(null);
            }
          });
        }

        ch = _client.channel('feed_home_${streamCtl.hashCode}');
        void sub(String table) {
          ch!.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) => bump(),
          );
        }

        sub('posts');
        sub('feed_comments');
        sub('feed_likes');
        ch!.subscribe();
      },
      onCancel: () {
        ch?.unsubscribe();
        ch = null;
      },
    );
    return streamCtl.stream;
  }
}
