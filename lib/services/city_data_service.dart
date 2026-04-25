import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/admin_config.dart';
import '../config/supabase_ready.dart';

/// Фиксированная строка расписания парома в `public.schedules`.
const String kFerryScheduleRowId = '00000000-0000-0000-0000-000000000001';

/// Loads news and ferry status; admin-only write operations.
class CityDataService {
  CityDataService._();

  static SupabaseClient? get client {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  /// Строка [profiles] по id пользователя (читать [first_name] и т.д.).
  static Future<Map<String, dynamic>?> fetchProfileRow(String userId) async {
    final c = client;
    if (c == null) {
      return null;
    }
    try {
      return await c.from('profiles').select().eq('id', userId).maybeSingle();
    } on Exception {
      return null;
    }
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

  /// Статус парома: одна запись [schedules] с `id` = [kFerryScheduleRowId].
  static Future<FerryStatusRow?> fetchFerryStatus() async {
    final c = client;
    if (c == null) {
      return null;
    }
    try {
      final Map<String, dynamic>? data = await c
          .from('schedules')
          .select()
          .eq('id', kFerryScheduleRowId)
          .maybeSingle();
      if (data == null) {
        return null;
      }
      return ferryFromScheduleRow(data);
    } on Exception {
      return null;
    }
  }

  /// Подписка на ленту новостей (Realtime + PostgREST).
  static Stream<List<Map<String, dynamic>>>? watchNewsList() {
    final c = client;
    if (c == null) {
      return null;
    }
    return c
        .from('news')
        .stream(primaryKey: const <String>['id'])
        .order('created_at', ascending: false);
  }

  /// Подписка на строку парома в [schedules].
  static Stream<List<Map<String, dynamic>>>? watchFerrySchedule() {
    final c = client;
    if (c == null) {
      return null;
    }
    return c
        .from('schedules')
        .stream(primaryKey: const <String>['id'])
        .eq('id', kFerryScheduleRowId);
  }

  static Future<void> updateFerryStatus({
    required String statusText,
    required bool isRunning,
    required String timeText,
  }) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String t = timeText.trim();
    await c.from('schedules').update(<String, dynamic>{
      'status_text': statusText,
      'is_running': isRunning,
      'time_text': t.isEmpty ? null : t,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', kFerryScheduleRowId);
  }

  static FerryStatusRow? ferryFromScheduleRow(Map<String, dynamic> m) {
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
    String? timeStr;
    final Object? t0 = m['time_text'];
    if (t0 is String && t0.trim().isNotEmpty) {
      timeStr = t0.trim();
    }
    if (id == null) {
      return null;
    }
    return FerryStatusRow(
      id: id,
      statusText: text,
      isRunning: run,
      timeText: timeStr,
    );
  }

  /// Только [kAdministratorEmail] в `auth.users` / JWT.
  static bool isCurrentUserAdminSync() {
    return _isAdministratorEmail(client?.auth.currentUser?.email);
  }

  static Future<bool> isCurrentUserAdmin() async {
    return isCurrentUserAdminSync();
  }

  static bool _isAdministratorEmail(String? email) {
    if (email == null) {
      return false;
    }
    return email.toLowerCase().trim() == kAdministratorEmail;
  }

  static const String newsImagesBucket = 'news-images';

  /// Медиа для новостей (фото и видео).
  static const String cityMediaBucket = 'city_media';

  /// Все маршруты автобусов, по номеру маршрута.
  static Future<List<BusScheduleRow>> fetchBusSchedules() async {
    final c = client;
    if (c == null) {
      return <BusScheduleRow>[];
    }
    try {
      final List<dynamic> res = await c
          .from('bus_schedules')
          .select()
          .order('route_number', ascending: true);
      return res
          .cast<Map<String, dynamic>>()
          .map(BusScheduleRow.fromMap)
          .whereType<BusScheduleRow>()
          .toList();
    } on Exception {
      return <BusScheduleRow>[];
    }
  }

  static Stream<List<Map<String, dynamic>>>? watchBusSchedules() {
    final c = client;
    if (c == null) {
      return null;
    }
    return c
        .from('bus_schedules')
        .stream(primaryKey: const <String>['id'])
        .order('route_number', ascending: true);
  }

  static Future<void> insertBusSchedule({
    required String routeNumber,
    required String destination,
    required List<String> departureTimes,
  }) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не инициализирован');
    }
    await c.from('bus_schedules').insert(<String, dynamic>{
      'route_number': routeNumber,
      'destination': destination,
      'departure_times': departureTimes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> updateBusSchedule({
    required Object id,
    required String routeNumber,
    required String destination,
    required List<String> departureTimes,
  }) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не инициализирован');
    }
    await c.from('bus_schedules').update(<String, dynamic>{
      'route_number': routeNumber,
      'destination': destination,
      'departure_times': departureTimes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteBusSchedule(Object id) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не инициализирован');
    }
    await c.from('bus_schedules').delete().eq('id', id);
  }

  static Future<void> insertNewsRow({
    required String category,
    required String title,
    required String body,
    String? author,
    String? mediaUrl,
    String? mediaType,
    int likes = 0,
    int comments = 0,
  }) async {
    final c = client;
    if (c == null) {
      throw StateError('Supabase не инициализирован');
    }
    await c.from('news').insert(<String, dynamic>{
      'category': category,
      'author': author ?? kAdministratorEmail,
      'title': title,
      'body': body,
      'media_url': mediaUrl,
      'media_type': mediaType,
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
    this.timeText,
  });
  /// id строки в [schedules] (int или uuid) — для .update
  final Object id;
  final String statusText;
  final bool isRunning;
  /// Подпись времени (колонка `time_text` в `schedules`), например ближайший рейс.
  final String? timeText;
}

class BusScheduleRow {
  const BusScheduleRow({
    required this.id,
    required this.routeNumber,
    required this.destination,
    required this.departureTimes,
  });

  final Object id;
  final String routeNumber;
  final String destination;
  final List<String> departureTimes;

  static BusScheduleRow? fromMap(Map<String, dynamic> m) {
    final Object? id = m['id'];
    if (id == null) {
      return null;
    }
    return BusScheduleRow(
      id: id,
      routeNumber: (m['route_number'] as String?)?.trim() ?? '',
      destination: (m['destination'] as String?)?.trim() ?? '',
      departureTimes: _parseStringList(m['departure_times']),
    );
  }
}

List<String> _parseStringList(Object? v) {
  if (v == null) {
    return <String>[];
  }
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  if (v is String && v.isNotEmpty) {
    return v
        .split(RegExp(r'[\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return <String>[];
}
