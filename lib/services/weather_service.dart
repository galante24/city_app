// Запросы к Open-Weather. Ключ и координаты: `lib/config/weather_config.dart`
// (ключ подставляется при сборке из `api_keys.json` / `--dart-define=OPENWEATHER_API_KEY`).

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/weather_config.dart';
import '../core/secure_log.dart';

/// Текущая погода (компакт для AppBar).
class WeatherCurrent {
  const WeatherCurrent({
    required this.tempC,
    required this.iconCode,
    this.main = 'Clouds',
  });

  final double tempC;
  final String iconCode;

  /// Поле `weather[0].main` OpenWeather (Clear, Clouds, Rain, …).
  final String main;
}

/// Один день в прогнозе.
class WeatherDayForecast {
  const WeatherDayForecast({
    required this.dateKey,
    required this.label,
    required this.tempMinC,
    required this.tempMaxC,
    required this.iconCode,
    required this.description,
  });

  final String dateKey;
  final String label;
  final double tempMinC;
  final double tempMaxC;
  final String iconCode;
  final String description;
}

class WeatherService {
  WeatherService._();

  static const String _base = 'https://api.openweathermap.org/data/2.5';

  static bool get hasApiKey => kOpenWeatherApiKey.isNotEmpty;

  static Map<String, String> get _queryBase => <String, String>{
    'lat': kWeatherLat.toString(),
    'lon': kWeatherLon.toString(),
    'appid': kOpenWeatherApiKey,
    'units': 'metric',
    'lang': 'ru',
  };

  static const Map<String, String> _httpHeaders = <String, String>{
    'User-Agent': 'CityApp-Flutter/1.0 (weather)',
  };

  static Future<WeatherCurrent?> fetchCurrent() async {
    if (!hasApiKey) {
      return null;
    }
    final Uri uri = Uri.parse('$_base/weather').replace(
      queryParameters: <String, String>{
        'q': 'Lesosibirsk',
        'appid': kOpenWeatherApiKey,
        'units': 'metric',
        'lang': 'ru',
      },
    );
    try {
      final http.Response r = await http
          .get(uri, headers: _httpHeaders)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        debugLogHttpFailure('Weather /weather', r.statusCode);
        return null;
      }
      final Object? j = jsonDecode(r.body);
      if (j is! Map) {
        return null;
      }
      final Map<String, dynamic> root = Map<String, dynamic>.from(j);
      final Object? m = root['main'];
      double? t;
      if (m is Map) {
        final num? n = m['temp'] as num?;
        t = n?.toDouble();
      }
      final List<dynamic>? w = root['weather'] as List<dynamic>?;
      String icon = '02d';
      String mainCond = 'Clouds';
      if (w != null && w.isNotEmpty && w.first is Map) {
        final Map<dynamic, dynamic> wd = w.first as Map<dynamic, dynamic>;
        icon = wd['icon'] as String? ?? icon;
        mainCond = wd['main'] as String? ?? mainCond;
      }
      if (t == null) {
        return null;
      }
      return WeatherCurrent(tempC: t, iconCode: icon, main: mainCond);
    } on Object catch (e) {
      debugLogHttpFailure('Weather fetchCurrent', null, error: e);
      return null;
    }
  }

  /// Прогноз на [totalDays] календарных дней, начиная с сегодня (по данным 3-ч API).
  static Future<List<WeatherDayForecast>> fetchForecastDays({
    int totalDays = 3,
  }) async {
    if (!hasApiKey) {
      return <WeatherDayForecast>[];
    }
    final Uri uri = Uri.parse(
      '$_base/forecast',
    ).replace(queryParameters: _queryBase);
    final http.Response r;
    try {
      r = await http
          .get(uri, headers: _httpHeaders)
          .timeout(const Duration(seconds: 25));
    } on Object catch (e) {
      debugLogHttpFailure('Weather forecast get', null, error: e);
      return <WeatherDayForecast>[];
    }
    if (r.statusCode != 200) {
      debugLogHttpFailure('Weather /forecast', r.statusCode);
      return <WeatherDayForecast>[];
    }
    final Object? decoded = jsonDecode(r.body);
    if (decoded is! Map) {
      return <WeatherDayForecast>[];
    }
    final Map<String, dynamic> j = Map<String, dynamic>.from(decoded);
    final List<dynamic>? list = j['list'] as List<dynamic>?;
    if (list == null) {
      return <WeatherDayForecast>[];
    }

    final Map<String, _DayAgg> byDay = <String, _DayAgg>{};
    for (final dynamic e in list) {
      if (e is! Map) {
        continue;
      }
      final Map<String, dynamic> entry = Map<String, dynamic>.from(e);
      final int? dt = (entry['dt'] as num?)?.toInt();
      if (dt == null) {
        continue;
      }
      final DateTime local = DateTime.fromMillisecondsSinceEpoch(
        dt * 1000,
        isUtc: true,
      ).toLocal();
      final String key =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      final Object? mainObj = entry['main'];
      if (mainObj is! Map) {
        continue;
      }
      final num? tnum = Map<String, dynamic>.from(mainObj)['temp'] as num?;
      if (tnum == null) {
        continue;
      }
      final double temp = tnum.toDouble();
      final List<dynamic>? wlist = entry['weather'] as List<dynamic>?;
      final String icon =
          wlist != null && wlist.isNotEmpty && wlist.first is Map
          ? (Map<dynamic, dynamic>.from(
                      wlist.first as Map<dynamic, dynamic>,
                    )['icon']
                    as String? ??
                '02d')
          : '02d';
      final String desc =
          wlist != null && wlist.isNotEmpty && wlist.first is Map
          ? (Map<dynamic, dynamic>.from(
                      wlist.first as Map<dynamic, dynamic>,
                    )['description']
                    as String? ??
                '')
          : '';
      byDay.putIfAbsent(key, () => _DayAgg());
      final _DayAgg a = byDay[key]!;
      if (a.minTemp == null || temp < a.minTemp!) {
        a.minTemp = temp;
      }
      if (a.maxTemp == null || temp > a.maxTemp!) {
        a.maxTemp = temp;
      }
      a.icons.add(icon);
      a.descs.add(desc);
    }

    final List<String> sortedKeys = byDay.keys.toList()
      ..sort((String a, String b) {
        final List<int> pa = a.split('-').map(int.parse).toList();
        final List<int> pb = b.split('-').map(int.parse).toList();
        final DateTime da = DateTime(pa[0], pa[1], pa[2]);
        final DateTime db = DateTime(pb[0], pb[1], pb[2]);
        return da.compareTo(db);
      });

    final DateTime now = DateTime.now();
    final DateTime startToday = DateTime(now.year, now.month, now.day);
    final List<String> dayKeys = sortedKeys.where((String k) {
      final List<int> p = k.split('-').map(int.parse).toList();
      final DateTime d = DateTime(p[0], p[1], p[2]);
      return !d.isBefore(startToday);
    }).toList();

    final int want = totalDays;
    final List<WeatherDayForecast> out = <WeatherDayForecast>[];
    for (int i = 0; i < dayKeys.length && out.length < want; i++) {
      final String k = dayKeys[i];
      final _DayAgg? a = byDay[k];
      if (a == null || a.minTemp == null || a.maxTemp == null) {
        continue;
      }
      final List<int> p = k.split('-').map(int.parse).toList();
      final DateTime d = DateTime(p[0], p[1], p[2]);
      final String label = _dayLabel(d, now);
      final String midIcon = a.icons.isNotEmpty
          ? a.icons[a.icons.length >> 1]
          : '02d';
      final String midDesc = a.descs.isNotEmpty
          ? a.descs[a.descs.length >> 1]
          : '';
      out.add(
        WeatherDayForecast(
          dateKey: k,
          label: label,
          tempMinC: a.minTemp!,
          tempMaxC: a.maxTemp!,
          iconCode: midIcon,
          description: midDesc,
        ),
      );
    }
    return out;
  }

  static String _dayLabel(DateTime d, DateTime now) {
    final DateTime t0 = DateTime(now.year, now.month, now.day);
    final DateTime t1 = DateTime(d.year, d.month, d.day);
    final int diff = t1.difference(t0).inDays;
    if (diff == 0) {
      return 'Сегодня';
    }
    if (diff == 1) {
      return 'Завтра';
    }
    const List<String> w = <String>[
      '',
      'пн',
      'вт',
      'ср',
      'чт',
      'пт',
      'сб',
      'вс',
    ];
    return w[d.weekday];
  }
}

class _DayAgg {
  double? minTemp;
  double? maxTemp;
  final List<String> icons = <String>[];
  final List<String> descs = <String>[];
}

String formatTempC(num t) {
  final int r = t.round();
  if (r > 0) {
    return '+$r°C';
  }
  return '$r°C';
}

String openWeatherIconUrl(String code, {String size = '2x'}) {
  return 'https://openweathermap.org/img/wn/$code@$size.png';
}
