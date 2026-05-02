/// Секреты **не** хранятся в репозитории.
///
/// **Порядок:**
/// 1. **Основной путь:** `const String.fromEnvironment('SUPABASE_URL')` и
///    `'SUPABASE_ANON_KEY'` — `flutter run/build --dart-define=…` или
///    `--dart-define-from-file=api_keys.json` (ключи запекаются в бандл, для web — в JS).
/// 2. Если define’ы пустые: [loadSupabaseRuntimeConfigIfMissing] — `api_keys.json` с диска (не web)
///    или HTTP `api_keys.json` относительно [Uri.base] (web, fallback после выкладки).
///
/// Формат `api_keys.example.json` — в корне проекта.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'supabase_overrides_stub.dart'
    if (dart.library.io) 'supabase_overrides_io.dart'
    as supabase_overrides;

/// Значения, **запечённые компилятором** (`--dart-define=…` / `--dart-define-from-file`).
///
/// Для web они попадают в JS-бандл на этапе `flutter build web` — это основной безопасный
/// путь для GitHub Actions (секреты в CI, не в репозитории).
const String kSupabaseUrlFromEnvironment = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);
const String kSupabaseAnonKeyFromEnvironment = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

/// Есть непустые compile-time define’ы (без ожидания I/O).
bool get kHasCompileTimeSupabaseDartDefines {
  return kSupabaseUrlFromEnvironment.trim().isNotEmpty &&
      kSupabaseAnonKeyFromEnvironment.trim().isNotEmpty;
}

/// Синхронно переносит trim define’ов в рабочие поля (если они заданы).
void syncCompileTimeSupabaseIntoResolved() {
  if (!kHasCompileTimeSupabaseDartDefines) {
    return;
  }
  _supabaseUrlResolved = kSupabaseUrlFromEnvironment.trim();
  _supabaseAnonKeyResolved = kSupabaseAnonKeyFromEnvironment.trim();
}

/// Рабочие значения: стартуют из [kSupabaseUrlFromEnvironment]; при пустых — подгрузка из JSON.
String _supabaseUrlResolved = kSupabaseUrlFromEnvironment;
String _supabaseAnonKeyResolved = kSupabaseAnonKeyFromEnvironment;

/// Текущий URL (после возможной подгрузки [loadSupabaseRuntimeConfigIfMissing]).
String get kSupabaseUrl => _supabaseUrlResolved;

/// Текущий anon key.
String get kSupabaseAnonKey => _supabaseAnonKeyResolved;

/// Подставляет ключи из `api_keys.json`, если compile-time define’ы пустые.
Future<void> loadSupabaseRuntimeConfigIfMissing() async {
  syncCompileTimeSupabaseIntoResolved();
  if (kHasCompileTimeSupabaseDartDefines) {
    return;
  }
  if (_supabaseUrlResolved.trim().isNotEmpty &&
      _supabaseAnonKeyResolved.trim().isNotEmpty) {
    return;
  }
  final Map<String, String>? fromDisk = await supabase_overrides
      .readApiKeysJsonFromProjectRoot();
  if (fromDisk != null) {
    final String? u = fromDisk['SUPABASE_URL']?.trim();
    final String? k = fromDisk['SUPABASE_ANON_KEY']?.trim();
    if (u != null && u.isNotEmpty) {
      _supabaseUrlResolved = u;
    }
    if (k != null && k.isNotEmpty) {
      _supabaseAnonKeyResolved = k;
    }
  }
  if (_supabaseUrlResolved.trim().isNotEmpty &&
      _supabaseAnonKeyResolved.trim().isNotEmpty) {
    return;
  }
  if (!kIsWeb) {
    return;
  }
  try {
    final Uri url = Uri.base.resolve('api_keys.json');
    final http.Response r = await http
        .get(url)
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200 || r.body.trim().isEmpty) {
      return;
    }
    final Object? decoded = jsonDecode(r.body);
    if (decoded is! Map) {
      return;
    }
    final Map<String, dynamic> m = Map<String, dynamic>.from(decoded);
    final String? u = m['SUPABASE_URL']?.toString().trim();
    final String? k = m['SUPABASE_ANON_KEY']?.toString().trim();
    if (u != null && u.isNotEmpty) {
      _supabaseUrlResolved = u;
    }
    if (k != null && k.isNotEmpty) {
      _supabaseAnonKeyResolved = k;
    }
  } on Object {
    // Опционально: статический api_keys.json рядом с index.html на хостинге.
  }
}

/// Корневой URL проекта `https://<ref>.supabase.co` без хвоста `/rest/v1` (сливаем при ошибке конфигурации).
String get kSupabaseProjectUrl {
  final String raw = kSupabaseUrl.trim();
  if (raw.isEmpty) {
    return '';
  }
  return _normalizeSupabaseProjectUrl(raw);
}

String _normalizeSupabaseProjectUrl(String url) {
  var s = url;
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  const String restSeg = '/rest/v1';
  if (s.toLowerCase().endsWith(restSeg)) {
    s = s.substring(0, s.length - restSeg.length);
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
  }
  return s;
}

/// `supabase` (по умолчанию) — чат через Supabase; `rest` — HTTP [kApiBaseUrl].
const String kBackendModeEnv = String.fromEnvironment(
  'BACKEND_MODE',
  defaultValue: 'supabase',
);

/// База REST чата (без завершающего `/`), при [BACKEND_MODE] = rest.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

/// Sentry DSN — только из окружения/define, не хранить в репозитории.
const String kSentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '',
);

/// Статический Bearer для chat-api (только dev/сервисный сценарий; в prod лучше Supabase [accessToken]).
const String kChatApiBearer = String.fromEnvironment(
  'CHAT_API_BEARER',
  defaultValue: '',
);

/// Список email админов UI (подсказки). **Реальные права — только в БД / RLS / Edge.**
const String kAdminEmailsEnv = String.fromEnvironment(
  'ADMIN_EMAILS',
  defaultValue: '',
);

/// HTTPS URL **манифеста** OTA (например `https://app.example.com/ota/version.json`).
/// Пусто — цепочка OTA с VPS не используется (остаётся [checkForAppUpdates] через Supabase, если настроен).
const String kUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue: '',
);

/// Доп. хосты для ссылки на APK (через запятую), если файл на CDN, не на том же хосте, что манифест.
/// Пусто — разрешён только тот же host, что у [kUpdateManifestUrl].
const String kUpdateTrustedApkHosts = String.fromEnvironment(
  'UPDATE_TRUSTED_APK_HOSTS',
  defaultValue: '',
);

/// `true` (по умолчанию) — в `version.json` обязателен `sha256`. Для разработки: `false` или `UPDATE_REQUIRE_SHA256=false`.
const String kUpdateRequireSha256Env = String.fromEnvironment(
  'UPDATE_REQUIRE_SHA256',
  defaultValue: 'true',
);

/// Требовать SHA-256 в манифесте (compile-time, см. [kUpdateRequireSha256Env]).
bool get kUpdateRequireSha256 =>
    kUpdateRequireSha256Env != 'false' &&
    kUpdateRequireSha256Env != '0' &&
    kUpdateRequireSha256Env != 'no';

/// True — заданы реальный URL и anon key (не плейсхолдеры из example).
bool get kAreSupabaseSecretsConfigured =>
    kSupabaseProjectUrl.isNotEmpty &&
    kSupabaseAnonKey.trim().isNotEmpty &&
    !_supabaseDefinesLookLikePlaceholder;

/// Ловит случай: скопировали пример с `your-project-ref…` → DNS на несуществующий хост.
bool get _supabaseDefinesLookLikePlaceholder {
  return _looksLikePlaceholderSupabaseUrl(kSupabaseUrl.trim()) ||
      _looksLikePlaceholderAnonKey(kSupabaseAnonKey.trim());
}

bool _looksLikePlaceholderSupabaseUrl(String raw) {
  if (raw.isEmpty) {
    return true;
  }
  final Uri? parsed = Uri.tryParse(raw);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    return true;
  }
  final String host = parsed.host.toLowerCase();
  if (host.contains('your-project')) {
    return true;
  }
  if (host.contains('changeme')) {
    return true;
  }
  return false;
}

bool _looksLikePlaceholderAnonKey(String k) {
  if (k.length < 120) {
    return true;
  }
  if (k.toLowerCase().contains('your-anon')) {
    return true;
  }
  // Реальный anon JWT от Supabase всегда начинается с eyJ…
  if (!k.startsWith('eyJ')) {
    return true;
  }
  return false;
}

/// Ключ хранения сессии GoTrue (совместимо с прежним SharedPreferences-ключом Supabase).
String authSessionStorageKeyForUrl(String supabaseUrl) {
  final Uri u = Uri.parse(_normalizeSupabaseProjectUrl(supabaseUrl.trim()));
  final String host = u.host;
  if (host.isEmpty) {
    return 'sb-auth-token';
  }
  final String first = host.split('.').first;
  return 'sb-$first-auth-token';
}
