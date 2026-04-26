// Статическое расписание автобусов (Лесосибирск).

import 'package:flutter/material.dart';

// --- time helpers ---

int timeToMinutes(String t) {
  final String s = t.trim();
  if (s.isEmpty) {
    return 0;
  }
  final List<String> p = s.split(':');
  if (p.length < 2) {
    return 0;
  }
  int h = int.tryParse(p[0]) ?? 0;
  final int m = int.tryParse(p[1]) ?? 0;
  if (h >= 0 && h < 4) {
    h += 24;
  }
  return h * 60 + m;
}

List<String> parseTimesString(String raw) {
  String s = raw
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'Военкомат:\s*'), '')
      .replaceAll(RegExp(r'[«»]А[«»]:\s*'), '');
  final List<String> out = <String>[];
  for (String part in s.split(RegExp(r'[\n,]+'))) {
    part = part.trim();
    if (part.isEmpty) {
      continue;
    }
    part = part.replaceAll(RegExp(r'\s+'), '');
    if (!part.contains(':')) {
      continue;
    }
    final List<String> q = part.split(':');
    if (q.length < 2) {
      continue;
    }
    final int? hh0 = int.tryParse(q[0]);
    final int? mm0 = int.tryParse(q[1]);
    if (hh0 == null || mm0 == null) {
      continue;
    }
    out.add('${q[0].padLeft(2, '0')}:${q[1].padLeft(2, '0')}');
  }
  out.sort((String a, String b) => timeToMinutes(a).compareTo(timeToMinutes(b)));
  final Set<String> seen = <String>{};
  return out.where((String t) => seen.add(t)).toList();
}

String? timeRangeLabel(Iterable<String> times) {
  final List<String> t = List<String>.from(times);
  if (t.isEmpty) {
    return null;
  }
  t.sort((a, b) => timeToMinutes(a).compareTo(timeToMinutes(b)));
  return '${t.first} – ${t.last}';
}

int _mDay(String t) => timeToMinutes(t) % 1440;

/// Утро 06:00–09:59, день 10:00–13:59, вечер 14:00–16:59, вечер/ночь 17:00+ и 00:00–05:59.
List<List<String>> byDayparts(List<String> sorted) {
  if (sorted.isEmpty) {
    return <List<String>>[
      <String>[],
      <String>[],
      <String>[],
      <String>[],
    ];
  }
  final List<String> s = List<String>.from(sorted);
  s.sort((a, b) => timeToMinutes(a).compareTo(timeToMinutes(b)));
  return <List<String>>[
    s
        .where(
          (String t) {
            final int m = _mDay(t);
            return m >= 6 * 60 && m <= 9 * 60 + 59;
          },
        )
        .toList(),
    s
        .where(
          (String t) {
            final int m = _mDay(t);
            return m >= 10 * 60 && m <= 13 * 60 + 59;
          },
        )
        .toList(),
    s
        .where(
          (String t) {
            final int m = _mDay(t);
            return m >= 14 * 60 && m <= 16 * 60 + 59;
          },
        )
        .toList(),
    s
        .where(
          (String t) {
            final int m = _mDay(t);
            return m >= 17 * 60 || m < 6 * 60;
          },
        )
        .toList(),
  ];
}

String bandClockRange(int index) {
  switch (index) {
    case 0:
      return '06:00 – 09:59';
    case 1:
      return '10:00 – 13:59';
    case 2:
      return '14:00 – 16:59';
    case 3:
    default:
      return '17:00 – 23:59';
  }
}

// --- маршрут 7 ---

const String _r7NorthVoenRaw =
    '06:18, 06:28, 06:38, 06:46, 07:02, 07:10, 07:18, 07:26, 07:28, 07:36, '
    '07:52, 08:00, 08:10, 08:22, 08:30, 08:38, 08:54, 09:02, 09:10, 09:18, '
    '09:20, 09:28, 09:44, 09:52, 10:14, 10:40, 11:02, 11:10, 11:26, 11:34, '
    '11:42, 11:50, 11:52, 12:00, 12:16, 12:24, 12:34, 12:46, 12:54, 13:02, '
    '13:18, 13:26, 13:34, 13:42, 13:44, 13:50, 13:52, 14:08, 14:16, 14:26, '
    '14:38, 14:46, 14:54, 15:10, 15:18, 15:26, 15:34, 16:16, 16:26, 16:30, '
    '16:40, 16:48, 16:58, 17:18, 17:26, 17:42, 17:50, 17:58, 18:06, 18:08, '
    '18:16, 18:32, 18:40, 18:50, 19:02, 19:10, 19:18, 19:34, 19:42, 19:50, '
    '19:58, 20:00, 20:08, 20:32, 21:04';
const String _r7NorthSportRaw =
    '06:36, 06:46, 06:56, 07:04, 07:20, 07:28, 07:36, 07:44, 07:46, 07:54, '
    '08:10, 08:18, 08:28, 08:40, 08:48, 08:56, 09:12, 09:20, 09:28, 09:36, '
    '09:38, 09:46, 10:02, 10:10, 10:32, 10:58, 11:20, 11:28, 11:44, 11:52, '
    '12:00, 12:08, 12:10, 12:18, 12:34, 12:42, 12:52, 13:04, 13:12, 13:20, '
    '13:36, 13:44, 13:52, 14:00, 14:02, 14:08, 14:10, 14:26, 14:34, 14:44, '
    '14:56, 15:04, 15:12, 15:28, 15:36, 15:44, 15:52, 16:34, 16:44, 16:48, '
    '16:58, 17:06, 17:16, 17:36, 17:44, 18:00, 18:08, 18:16, 18:24, 18:26, '
    '18:34, 18:50, 18:58, 19:08, 19:20, 19:28, 19:36, 19:52, 20:00, 20:08, '
    '20:16, 20:18, 20:26, 20:50, 21:22';
const String _r7SouthMkrRaw =
    '06:32, 06:40, 06:56, 07:04, 07:14, 07:26, 07:34, 07:42, 07:58, 08:06, '
    '08:14, 08:22, 08:24, 08:32, 08:48, 08:56, 09:06, 09:18, 09:26, 09:34, '
    '09:50, 09:58, 10:06, 10:14, 10:56, 11:04, 11:10, 11:20, 11:28, 11:38, '
    '11:58, 12:06, 12:22, 12:30, 12:38, 12:46, 12:48, 12:56, 13:12, 13:20, '
    '13:30, 13:42, 13:50, 13:58, 14:14, 14:22, 14:30, 14:38, 15:20, 15:22, '
    '15:28, 15:34, 15:42, 15:44, 15:50, 15:52, 16:06, 16:14, 16:22, 16:30, '
    '17:12, 17:20, 17:26, 17:36, 17:44, 17:54, 18:14, 18:22, 18:38, 18:46, '
    '18:54, 19:02, 19:04, 19:12, 19:28, 19:36, 19:46, 19:58, 20:06, 20:14, '
    '20:30, 20:58, 21:28';
const String _r7SouthSportRaw =
    '07:02, 07:10, 07:26, 07:34, 07:44, 07:56, 08:04, 08:12, 08:28, 08:36, '
    '08:44, 08:52, 08:54, 09:02, 09:18, 09:26, 09:36, 09:48, 09:56, 10:04, '
    '10:20, 10:28, 10:36, 10:44, 11:26, 11:34, 11:40, 11:50, 11:58, 12:08, '
    '12:28, 12:36, 12:52, 13:00, 13:08, 13:16, 13:18, 13:26, 13:42, 13:50, '
    '14:00, 14:12, 14:20, 14:28, 14:44, 14:52, 15:00, 15:08, 15:50, 15:52, '
    '15:58, 16:04, 16:12, 16:14, 16:20, 16:22, 16:36, 16:44, 16:52, 17:00, '
    '17:42, 17:50, 17:56, 18:06, 18:14, 18:24, 18:44, 18:52, 19:08, 19:16, '
    '19:24, 19:32, 19:34, 19:42, 19:58, 20:06, 20:16, 20:28, 20:36, 20:44, '
    '21:00, 21:28, 21:58';

List<String> get route7NorthVoen => parseTimesString(_r7NorthVoenRaw);
List<String> get route7NorthSport => parseTimesString(_r7NorthSportRaw);
List<String> get route7SouthMkr => parseTimesString(_r7SouthMkrRaw);
List<String> get route7SouthSport => parseTimesString(_r7SouthSportRaw);

// --- остальные маршруты (два конца или две крупные остановки) ---

const String _r1Voen =
    '20:16, 20:38, 20:58, 21:16, 21:32, 21:48, 22:16, 22:28, 22:52, 23:08, 23:24, 23:42';
const String _r1Mkr =
    '20:18, 20:38, 20:54, 21:12, 21:34, 21:54, 22:16, 22:30, 22:44, 23:12, 23:26, 23:40, 00:02';

const String _r3Mkr = '06:22, 08:07, 10:50, 12:40, 15:25, 17:15, 19:30';
const String _r3School = '07:07, 09:07, 11:40, 13:45, 16:15, 18:05, 20:20';

const String _r4Voen =
    '06:35, 07:41, 08:01, 08:51, 09:21, 10:55, 11:30, 12:05, 13:05, 13:15, 14:12, 15:59, 16:50, 17:19, 18:11, 18:39, 20:10';
const String _r4Burm = '07:05, 07:15, 08:16, 08:41, 09:26, 10:01, 11:31, 12:21, 12:36, 13:30, 14:15, 14:51, 16:39, 17:25, 17:59, 18:51, 19:19';

const String _r5Voen =
    '06:54, 07:30, 08:14, 08:46, 09:22, 10:02, 11:18, 11:54, 12:38, 13:10, 13:46, 14:30, 15:02, 15:38, 17:02, 17:34, 18:10, 18:54, 20:02, 20:44';
const String _r5Kol =
    '06:35, 07:18, 07:50, 08:26, 09:10, 09:42, 10:18, 11:02, 12:14, 12:50, 13:34, 14:06, 14:42, 15:16, 15:58, 16:34, 17:56, 18:30, 19:06, 19:50, 21:15, 21:40';

const String _r12Voen =
    '06:30, 07:09, 08:01, 08:49, 10:23, 11:31, 12:13, 13:11, 13:53, 14:51, 16:13, 17:11, 17:57, 18:51, 19:37, 20:21';
const String _r12Mir =
    '06:30, 07:12, 08:00, 09:01, 09:35, 11:23, 12:21, 13:03, 14:01, 14:43, 15:41, 17:03, 18:01, 18:47, 19:41, 20:17';

const String _r13Voen =
    '06:13, 06:51, 07:21, 07:49, 08:11, 08:39, 09:11, 09:31, 10:41, 11:01, 11:17, 12:01, 12:21, 12:37, 13:39, 14:21, 14:39, 15:21, 15:41, 15:59, 16:41, 17:01, 17:39, 18:21, 18:41, 19:59, 21:07, 22:15';
const String _r13School =
    '06:47, 07:08, 07:30, 07:59, 08:30, 08:50, 09:19, 09:50, 10:11, 11:21, 11:41, 11:57, 12:41, 12:59, 13:27, 14:19, 15:01, 15:19, 16:01, 16:21, 16:39, 17:21, 17:41, 18:19, 19:01, 19:21, 20:35, 21:41, 22:49';

const String _r23Voen =
    '06:34, 06:42, 06:44, 06:58, 07:06, 07:14, 07:22, 07:32, 07:40, 07:46, 07:56, 08:04, 08:12, 08:18, 08:26, 08:34, 08:42, 08:50, 08:58, 09:06, 09:14, 09:24, 09:32, 09:38, 09:48, 09:56, 10:04, 10:10, 10:56, 11:06, 11:14, 11:22, 11:30, 11:38, 11:46, 11:56, 12:04, 12:10, 12:20, 12:28, 12:36, 12:42, 12:50, 12:58, 13:06, 13:14, 13:22, 13:30, 13:38, 13:48, 13:56, 14:02, 14:12, 14:20, 14:28, 14:34, 14:42, 14:50, 14:58, 15:06, 15:14, 15:22, 15:30, 15:54, 16:20, 16:22, 16:26, 16:28, 16:44, 16:52, 17:14, 17:22, 17:30, 17:38, 17:46, 17:54, 18:02, 18:12, 18:20, 18:26, 18:36, 18:44, 18:52, 18:58, 19:06, 19:14, 19:22, 19:30, 19:38, 19:46, 19:54, 20:04, 20:18, 20:40';
const String _r23Mkr =
    '06:36, 06:44, 06:50, 07:00, 07:08, 07:16, 07:22, 07:30, 07:38, 07:46, 07:54, 08:02, 08:10, 08:18, 08:28, 08:36, 08:42, 08:52, 09:00, 09:08, 09:14, 09:22, 09:30, 09:38, 09:46, 09:54, 10:02, 10:10, 10:22, 10:34, 10:58, 11:00, 11:02, 11:06, 11:24, 11:32, 11:54, 12:02, 12:10, 12:18, 12:26, 12:34, 12:42, 12:52, 13:00, 13:06, 13:16, 13:24, 13:32, 13:38, 13:46, 13:54, 14:02, 14:10, 14:18, 14:26, 14:34, 14:46, 14:58, 15:24, 15:26, 15:26, 15:30, 15:38, 15:46, 15:48, 15:54, 15:56, 16:02, 16:10, 16:18, 16:26, 16:50, 17:18, 17:22, 17:24, 17:40, 17:48, 18:10, 18:18, 18:26, 18:34, 18:42, 18:50, 18:58, 19:08, 19:22, 19:32, 19:40, 19:48, 19:54, 20:02, 20:10, 20:26, 20:46';

class SimpleBusRoute {
  const SimpleBusRoute({
    required this.number,
    required this.title,
    required this.labelA,
    required this.labelB,
    required this.color,
    this.rawTimesA = '',
    this.rawTimesB = '',
  });
  final int number;
  final String title;
  final String labelA;
  final String labelB;
  final Color color;
  final String rawTimesA;
  final String rawTimesB;

  List<String> get timesA => parseTimesString(rawTimesA);
  List<String> get timesB => parseTimesString(rawTimesB);
  String? get workHoursLabel =>
      timeRangeLabel(<String>[...timesA, ...timesB]);
}

List<SimpleBusRoute> get lesosibirskOtherBusRoutes {
  return <SimpleBusRoute>[
    const SimpleBusRoute(
      number: 1,
      title: 'Военкомат — мкр. «А»',
      labelA: 'Военкомат',
      labelB: 'Микрорайон «А»',
      color: Color(0xFFFF9800),
      rawTimesA: _r1Voen,
      rawTimesB: _r1Mkr,
    ),
    const SimpleBusRoute(
      number: 3,
      title: 'мкр. «А» — «Маяк» — школа № 18',
      labelA: 'мкр. «А»',
      labelB: 'школа № 18',
      color: Color(0xFF9C27B0),
      rawTimesA: _r3Mkr,
      rawTimesB: _r3School,
    ),
    const SimpleBusRoute(
      number: 4,
      title: 'Военкомат — Бурмакино',
      labelA: 'Военкомат',
      labelB: 'Бурмакино',
      color: Color(0xFF1976D2),
      rawTimesA: _r4Voen,
      rawTimesB: _r4Burm,
    ),
    const SimpleBusRoute(
      number: 5,
      title: 'Военкомат — Колесниково',
      labelA: 'Военкомат',
      labelB: 'Колесниково',
      color: Color(0xFF2E7D32),
      rawTimesA: _r5Voen,
      rawTimesB: _r5Kol,
    ),
    const SimpleBusRoute(
      number: 12,
      title: 'Военкомат — п. Мирный',
      labelA: 'Военкомат',
      labelB: 'п. Мирный',
      color: Color(0xFF4FC3F7),
      rawTimesA: _r12Voen,
      rawTimesB: _r12Mir,
    ),
    const SimpleBusRoute(
      number: 13,
      title: 'Военкомат — школа № 18',
      labelA: 'Военкомат',
      labelB: 'школа № 18',
      color: Color(0xFFE91E63),
      rawTimesA: _r13Voen,
      rawTimesB: _r13School,
    ),
    const SimpleBusRoute(
      number: 23,
      title: 'Военкомат — 7 мкр — ОРС — мкр. «А»',
      labelA: 'Военкомат',
      labelB: 'мкр. «А»',
      color: Color(0xFFFFC107),
      rawTimesA: _r23Voen,
      rawTimesB: _r23Mkr,
    ),
  ];
}
