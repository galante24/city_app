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

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from(_tasks)
          .select()
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
          .select()
          .eq('task_id', taskId)
          .order('created_at', ascending: true);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> addComment(String taskId, String text) async {
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
    await c.from(_comments).insert(<String, dynamic>{
      'task_id': taskId,
      'user_id': uid,
      'text': t,
    });
  }
}
