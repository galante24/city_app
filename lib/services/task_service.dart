import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

class TaskService {
  TaskService._();

  static SupabaseClient? get _c {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  static const String _tasks = 'tasks';
  static const String _comments = 'task_comments';

  static const String _taskSelectWithAuthor = '''
*,
author:profiles!tasks_author_id_fkey(
  id,
  first_name,
  last_name,
  username,
  avatar_url
)
''';

  static const String _taskCommentSelectWithAuthor = '''
*,
author:profiles!task_comments_user_id_fkey(
  id,
  first_name,
  last_name,
  username,
  avatar_url
)
''';

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from(_tasks)
          .select(_taskSelectWithAuthor)
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> insert({
    required String title,
    required String description,
    String? phone,
    double? price,
  }) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? uid = c.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    final String? p = phone?.trim();
    await c.from(_tasks).insert(<String, dynamic>{
      'author_id': uid,
      'title': title.trim(),
      'description': description.trim(),
      if (p != null && p.isNotEmpty) 'phone': p,
      if (price != null && price > 0) 'price': price,
    });
  }

  static Future<void> deleteById(String id) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from(_tasks).delete().eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> fetchComments(String taskId) async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from(_comments)
          .select(_taskCommentSelectWithAuthor)
          .eq('task_id', taskId)
          .order('created_at', ascending: true);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> addComment(
    String taskId,
    String text, {
    String? parentId,
  }) async {
    final c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? uid = c.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    final String t = text.trim();
    if (t.isEmpty) {
      return;
    }
    final String? pp = parentId?.trim();
    await c.from(_comments).insert(<String, dynamic>{
      'task_id': taskId,
      'user_id': uid,
      'text': t,
      if (pp != null && pp.isNotEmpty) 'parent_id': pp,
    });
  }
}
