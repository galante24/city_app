import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import 'city_data_service.dart';

/// Заведения: места, подписки, модераторы, посты, лайки, комментарии.
class PlaceService {
  PlaceService._();

  static SupabaseClient? get _c {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  static Future<List<Map<String, dynamic>>> fetchPlaces() async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('places')
          .select()
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>?> fetchPlace(String id) async {
    final c = _c;
    if (c == null) {
      return null;
    }
    try {
      return await c.from('places').select().eq('id', id).maybeSingle();
    } on Exception {
      return null;
    }
  }

  static Future<Set<String>> fetchMySubscribedPlaceIds() async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return <String>{};
    }
    try {
      final List<dynamic> rows = await c
          .from('place_subscriptions')
          .select('place_id')
          .eq('user_id', uid);
      return rows
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => m['place_id']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toSet();
    } on Exception {
      return <String>{};
    }
  }

  static Future<bool> isSubscribed(String placeId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return false;
    }
    try {
      final Map<String, dynamic>? row = await c
          .from('place_subscriptions')
          .select('place_id')
          .eq('user_id', uid)
          .eq('place_id', placeId)
          .maybeSingle();
      return row != null;
    } on Exception {
      return false;
    }
  }

  static Future<void> subscribe(String placeId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from('place_subscriptions').insert(<String, dynamic>{
      'user_id': uid,
      'place_id': placeId,
    });
  }

  static Future<void> unsubscribe(String placeId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c
        .from('place_subscriptions')
        .delete()
        .eq('user_id', uid)
        .eq('place_id', placeId);
  }

  static Future<List<String>> fetchModeratorUserIds(String placeId) async {
    final c = _c;
    if (c == null) {
      return <String>[];
    }
    try {
      final List<dynamic> rows = await c
          .from('place_moderators')
          .select('user_id')
          .eq('place_id', placeId);
      return rows
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => m['user_id']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
    } on Exception {
      return <String>[];
    }
  }

  /// Модераторы заведения с полями профиля для UI (порядок как в [place_moderators]).
  static Future<List<Map<String, dynamic>>> fetchPlaceModeratorsWithProfiles(
    String placeId,
  ) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> modRows = await c
          .from('place_moderators')
          .select('user_id')
          .eq('place_id', placeId);
      final List<String> ids = modRows
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => m['user_id']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
      if (ids.isEmpty) {
        return <Map<String, dynamic>>[];
      }
      final List<dynamic> profRows = await c
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url')
          .inFilter('id', ids);
      final Map<String, Map<String, dynamic>> byId =
          <String, Map<String, dynamic>>{};
      for (final dynamic p in profRows) {
        final Map<String, dynamic> m = p as Map<String, dynamic>;
        final String id = m['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          byId[id] = m;
        }
      }
      return ids
          .map(
            (String id) => <String, dynamic>{
              'user_id': id,
              'username': byId[id]?['username'],
              'first_name': byId[id]?['first_name'],
              'last_name': byId[id]?['last_name'],
              'avatar_url': byId[id]?['avatar_url'],
            },
          )
          .toList();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  /// Клиентская проверка: совпадает с [public.can_moderate_place] (владелец, модераторы,
  /// [profiles.is_admin]; флаг [isDbAdmin] — как у [CityDataService.isProfilesOrEmailAdmin]).
  static Future<bool> canModeratePlace(
    String placeId, {
    required bool isDbAdmin,
    required List<String> moderatorIds,
    String? ownerId,
  }) async {
    final String? me = _c?.auth.currentUser?.id;
    if (me == null) {
      return false;
    }
    if (isDbAdmin) {
      return true;
    }
    if (ownerId != null && ownerId == me) {
      return true;
    }
    return moderatorIds.contains(me);
  }

  static Future<String> uploadPlaceImage(XFile file) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? uid = c.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    final String name = file.name;
    final int dot = name.lastIndexOf('.');
    final String ext = dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : 'jpg';
    final String path =
        'places/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final String contentType = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final bucket = c.storage.from(CityDataService.cityMediaBucket);
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
    } else {
      await bucket.upload(
        path,
        File(file.path),
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
    }
    return bucket.getPublicUrl(path);
  }

  static Future<String> createPlace({
    required String title,
    String description = '',
    String? photoUrl,
    String? coverUrl,
  }) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    final Map<String, dynamic> row = await c
        .from('places')
        .insert(<String, dynamic>{
          'title': title.trim(),
          'description': description.trim(),
          'owner_id': uid,
          if (photoUrl != null && photoUrl.isNotEmpty) 'photo_url': photoUrl,
          if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
        })
        .select('id')
        .single();
    return row['id']?.toString() ?? '';
  }

  static Future<void> updatePlace(
    String placeId,
    Map<String, dynamic> patch,
  ) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    if (patch.isEmpty) {
      return;
    }
    patch['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await c.from('places').update(patch).eq('id', placeId);
  }

  /// Удаление заведения (RLS: только администратор профиля).
  static Future<void> deletePlace(String placeId) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from('places').delete().eq('id', placeId);
  }

  static Future<void> addModerator(String placeId, String userId) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from('place_moderators').insert(<String, dynamic>{
      'place_id': placeId,
      'user_id': userId,
    });
  }

  /// Снять модератора (RLS: только администратор профиля; дублируем проверку на клиенте).
  static Future<void> removeModerator(String placeId, String userId) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    if (!await CityDataService.isProfilesOrEmailAdmin()) {
      throw StateError('Только администратор может снять модератора');
    }
    await c
        .from('place_moderators')
        .delete()
        .eq('place_id', placeId)
        .eq('user_id', userId);
  }

  static Future<Map<String, dynamic>?> fetchPlacePostById(String postId) async {
    final c = _c;
    if (c == null) {
      return null;
    }
    try {
      return await c
          .from('place_posts')
          .select(_placePostSelectWithAuthor)
          .eq('id', postId)
          .maybeSingle();
    } on Exception {
      return null;
    }
  }

  static const String _placePostSelectWithAuthor = '''
*,
author:profiles!place_posts_author_id_fkey(
  id,
  first_name,
  last_name,
  username,
  avatar_url
)
''';

  static const String _placeCommentSelectWithAuthor = '''
*,
author:profiles!place_post_comments_user_id_fkey(
  id,
  first_name,
  last_name,
  username,
  avatar_url
)
''';

  static Future<List<Map<String, dynamic>>> fetchPosts(String placeId) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('place_posts')
          .select(_placePostSelectWithAuthor)
          .eq('place_id', placeId)
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>> createPost({
    required String placeId,
    required String content,
    String? imageUrl,
    required bool notifySubscribers,
  }) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    final Map<String, dynamic> row = await c
        .from('place_posts')
        .insert(<String, dynamic>{
          'place_id': placeId,
          'author_id': uid,
          'content': content.trim(),
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'notify_subscribers': notifySubscribers,
        })
        .select(_placePostSelectWithAuthor)
        .single();
    return row;
  }

  static Future<bool> isPostLikedByMe(String postId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return false;
    }
    try {
      final Map<String, dynamic>? row = await c
          .from('place_post_likes')
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', uid)
          .maybeSingle();
      return row != null;
    } on Exception {
      return false;
    }
  }

  static Future<void> likePost(String postId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from('place_post_likes').insert(<String, dynamic>{
      'post_id': postId,
      'user_id': uid,
    });
  }

  static Future<void> unlikePost(String postId) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c
        .from('place_post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', uid);
  }

  static Future<List<Map<String, dynamic>>> fetchComments(
    String postId,
  ) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('place_post_comments')
          .select(_placeCommentSelectWithAuthor)
          .eq('post_id', postId)
          .order('created_at', ascending: true);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> addComment(String postId, String text) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    final String t = text.trim();
    if (t.isEmpty) {
      return;
    }
    await c.from('place_post_comments').insert(<String, dynamic>{
      'post_id': postId,
      'user_id': uid,
      'content': t,
    });
  }

  static Future<void> updateMyNotificationsEnabled(bool enabled) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      throw StateError('Нет сессии');
    }
    await c.from('profiles').update(<String, dynamic>{
      'notifications_enabled': enabled,
    }).eq('id', uid);
  }

  static Future<void> updateMyFcmToken(String? token) async {
    final c = _c;
    final String? uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      return;
    }
    await c.from('profiles').update(<String, dynamic>{
      'fcm_token': token,
    }).eq('id', uid);
  }

  // ---------- menu_items (цифровое меню) ----------

  static Future<List<Map<String, dynamic>>> fetchMenuItems(
    String placeId,
  ) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('menu_items')
          .select()
          .eq('place_id', placeId)
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>> insertMenuItem({
    required String placeId,
    required String title,
    String description = '',
    String category = '',
    required num price,
    num? oldPrice,
    String? photoUrl,
    bool isAvailable = true,
  }) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final Map<String, dynamic> data = <String, dynamic>{
      'place_id': placeId,
      'title': title.trim(),
      'description': description.trim(),
      'category': category.trim(),
      'price': price,
      'is_available': isAvailable,
    };
    if (oldPrice != null) {
      data['old_price'] = oldPrice;
    }
    final String? pu = photoUrl?.trim();
    if (pu != null && pu.isNotEmpty) {
      data['photo_url'] = pu;
    }
    final Map<String, dynamic> row =
        await c.from('menu_items').insert(data).select().single();
    return row;
  }

  static Future<void> updateMenuItem(
    String itemId,
    Map<String, dynamic> patch,
  ) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    if (patch.isEmpty) {
      return;
    }
    await c.from('menu_items').update(patch).eq('id', itemId);
  }

  static Future<void> deleteMenuItem(String itemId) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from('menu_items').delete().eq('id', itemId);
  }

  /// Фото позиции меню: тот же бакет [CityDataService.cityMediaBucket], путь под `places/`.
  static Future<String> uploadMenuItemPhoto(XFile file) async {
    return uploadPlaceImage(file);
  }
}
