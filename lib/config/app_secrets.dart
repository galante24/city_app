/// Секреты **не** хранятся в репозитории. Задаются при сборке/запуске:
/// `flutter run --dart-define-from-file=api_keys.json`
/// или `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
///
/// Формат `api_keys.example.json` — в корне проекта.
library;

const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);

const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

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

/// True — в сборку попали реальный URL и anon key (не плейсхолдеры из example).
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
