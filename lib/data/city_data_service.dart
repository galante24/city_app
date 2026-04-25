import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Loads news and ferry status; admin-only write operations.
class CityDataService {
  CityDataService._();

  static SupabaseClient? get client {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  /// Все публикации; на главной фильтр по [category] — см. `_categoryFromDb` / вкладки.
  static Future<List<Map<String, dynamic>>> fetchNews() async {
    final c = client;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> res = await c
          .from('news')
          .select()
          .order('created_at', ascending: false);
      return res.cast<Map<String, dynamic>>();
    } on Exception {
      return <Map<String, dynamic>>[];
    }
  }

  /// Статус парома: строка из [schedules] (по id=1, иначе первая запись).
  static Future<FerryStatusRow?> fetchFerryStatus() async {
    final c = client;
    if (c == null) {
      return null;
    }
    try {
      Map<String, dynamic>? data = await c
          .from('schedules')
          .select()
          .eq('id', 1)
          .maybeSingle();
      data ??= await c
          .from('schedules')
          .select()
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();
      if (data == null) {
        return null;
      }
      return _ferryFromScheduleRow(data);
    } on Exception {
      return null;
    }
  }

  static Future<void> updateFerryStatus({
    required String statusText,
    required bool isRunning,
    required Object rowId,
  }) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.from('schedules').update(<String, dynamic>{
      'status_text': statusText,
      'is_running': isRunning,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rowId);
  }

  static FerryStatusRow? _ferryFromScheduleRow(Map<String, dynamic> m) {
    final Object? id = m['id'];
    final String text = (m['status_text'] as String?) ??
        (m['title'] as String?) ??
        (m['description'] as String?) ??
        (m['name'] as String?) ??
        (m['label'] as String?) ??
        (m['message'] as String?) ??
        '';
    final bool run = (m['is_running'] as bool?) ??
        (m['is_active'] as bool?) ??
        (m['active'] as bool?) ??
        true;
    if (id == null) {
      return null;
    }
    return FerryStatusRow(
      id: id,
      statusText: text,
      isRunning: run,
    );
  }

  static Future<bool> isCurrentUserAdmin() async {
    final c = client;
    if (c == null) {
      return false;
    }
    final user = c.auth.currentUser;
    if (user == null) {
      return false;
    }
    try {
      final row = await c
          .from('profiles')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) {
        return false;
      }
      return (row['is_admin'] as bool?) ?? false;
    } on Exception {
      return false;
    }
  }

  static const String newsImagesBucket = 'news-images';

  static Future<void> insertNewsRow({
    required String category,
    required String author,
    required String title,
    String? imageUrl,
    String? videoUrl,
    int likes = 0,
    int comments = 0,
  }) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не инициализирован');
    }
    await c.from('news').insert(<String, dynamic>{
      'category': category,
      'author': author,
      'title': title,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'likes': likes,
      'comments': comments,
    });
  }
}

class FerryStatusRow {
  const FerryStatusRow({
    required this.id,
    required this.statusText,
    required this.isRunning,
  });
  /// id строки в [schedules] (int или uuid) — для .update
  final Object id;
  final String statusText;
  final bool isRunning;
}
