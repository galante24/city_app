import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post.dart';

/// Получает и транслирует посты через Supabase (REST + Realtime).
class PostService {
  PostService(this._client);

  final SupabaseClient _client;

  static const String _table = 'posts';

  Future<List<Post>> getPosts() async {
    final List<dynamic> rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return rows
        .map(
          (dynamic e) => Post.fromJson(
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
          ),
        )
        .toList();
  }

  Future<void> createPost(String title, String content) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Пользователь не авторизован');
    }
    final String t = title.trim();
    final String c = content.trim();
    if (t.isEmpty || c.isEmpty) {
      throw ArgumentError('Заголовок и текст не могут быть пустыми');
    }
    await _client.from(_table).insert(<String, dynamic>{
      'title': t,
      'content': c,
      'user_id': user.id,
      'category': 'discussion',
      'image_urls': <String>[],
    });
  }

  Future<void> deletePost(String id) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Пользователь не авторизован');
    }
    final String trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Некорректный идентификатор поста');
    }
    await _client.from(_table).delete().eq('id', trimmed);
  }

  /// Первоначальный список + обновления по Realtime.
  Stream<List<Post>> streamPosts() {
    RealtimeChannel? channel;

    Future<void> push(StreamController<List<Post>> ctl) async {
      try {
        final List<Post> list = await getPosts();
        if (!ctl.isClosed) {
          ctl.add(list);
        }
      } catch (e, s) {
        if (!ctl.isClosed) {
          ctl.addError(e, s);
        }
      }
    }

    late StreamController<List<Post>> ctl;
    ctl = StreamController<List<Post>>(
      onListen: () {
        unawaited(
          Future<void>(() async {
            await push(ctl);
            channel = _client.channel('posts_channel_${ctl.hashCode}');
            channel!
                .onPostgresChanges(
                  event: PostgresChangeEvent.all,
                  schema: 'public',
                  table: _table,
                  callback: (PostgresChangePayload _) =>
                      scheduleMicrotask(() => push(ctl)),
                )
                .subscribe();
          }),
        );
      },
      onCancel: () {
        channel?.unsubscribe();
        channel = null;
      },
    );

    return ctl.stream;
  }
}
