# OTA-обновления Android (VPS, без Google Play)

## Схема

1. На VPS: HTTPS, nginx раздаёт `version.json` и `city_app.apk`.
2. Сборка: `flutter build apk --release` (локально или GitHub Actions).
3. Клиент: `UPDATE_MANIFEST_URL` (HTTPS) → сравнение `version_code` → скачивание → `sha256` → установщик.

## Почему не iOS

Публичная установка **IPA вне App Store** на обычные устройства Apple запрещена политикой (нужен TestFlight, Enterprise Program или MDM). Один «APK-аналог» для iOS **без** участия Apple — незаконен для массовой аудитории. Реализован только **Android** (как в задаче).

## Сервер (Timeweb / VPS)

### Каталог

```text
/var/www/ota/
  version.json
  city_app.apk
```

Права: владелец `www-data` (или от nginx), чтение для nginx.

### Nginx (пример `server` для HTTPS)

```nginx
server {
    listen 443 ssl http2;
    server_name app.example.com;

    ssl_certificate     /etc/letsencrypt/live/app.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.example.com/privkey.pem;
    # ssl_stapling on;  # рекомендуется для prod

    root /var/www/ota;
    default_type application/octet-stream;

    # JSON без кэша (актуальная версия)
    location = /version.json {
        add_header Cache-Control "no-store, no-cache, must-revalidate" always;
        default_type application/json;
    }

    # APK: только HTTPS; при необходимости сузьте IP (allow/deny) или токен в query
    location /city_app.apk {
        add_header Content-Disposition 'attachment; filename="city_app.apk"';
    }
}
```

```bash
sudo certbot --nginx -d app.example.com
```

### Безопасность

- Только **HTTPS** — URL в `UPDATE_MANIFEST_URL` и в поле `url` в JSON.
- **SHA-256** в `version.json` — **по умолчанию обязателен** в клиенте (`UPDATE_REQUIRE_SHA256`, отключайте `false` только в dev). Защита от битой/подменённой загрузки (TLS + целостность).
- **HTTP-редиректы** ограничены по длине цепочки; финальный host манифеста = host из `UPDATE_MANIFEST_URL` (нельзя «переехать» на чужой домен). Финальный URL APK — проверяется к политике host (и после редиректов), как поле `url` в манифесте.
- Успех только **HTTP 200** при загрузке `version.json` и файла `.apk` (4xx/5xx/301 без успешного тела — не update).
- **Подпись APK** — при установке Android проверяет, что пакет подписан тем же ключом, что и установленное приложение (см. `key.properties` / release keystore). Для prod подписывайте **тем же** ключом, что в магазине/прошлых установках.
- **Жёсткая политика URL** в клиенте: ссылка на APK — **тот же host**, что `version.json` (либо в `UPDATE_TRUSTED_APK_HOSTS`), сравнение **без учёта регистра** в DNS-именах.
- Секреты: **только** GitHub Secrets (ключ SSH, не коммитить), данные `supabase`/`UPDATE_*` — в `--dart-define-from-file` при сборке.

## Формат `version.json`

```json
{
  "version": "1.0.1",
  "version_code": 7,
  "url": "https://app.example.com/city_app.apk",
  "sha256": "64_hex_symbols",
  "force": false,
  "min_version_code": 0
}
```

- `version` — отображаемая строка.
- `version_code` — **сравнение** с `+N` в `pubspec.yaml` (как `versionCode` в Android).
- `url` — тот же host, что манифест, или доверенный в `UPDATE_TRUSTED_APK_HOSTS`.
- `force` / `min_version_code` — нельзя нажать «Позже», если `force: true` или `local < min_version_code`.

## Flutter (сборка)

```bash
flutter build apk --release --dart-define-from-file=api_keys.json
```

В `api_keys.json` добавьте (помимо существующих полей):

```json
"UPDATE_MANIFEST_URL": "https://app.example.com/version.json",
"UPDATE_TRUSTED_APK_HOSTS": ""
```

Для CDN-файла на другом host:

`"UPDATE_TRUSTED_APK_HOSTS": "cdn.example.com"`

## GitHub Actions

Файл: `.github/workflows/android-ota-deploy.yml`.

**Secrets (репозиторий → Settings → Actions → New repository secret):**

| Secret | Пример |
|--------|--------|
| `OTA_SSH_HOST` | `app.example.com` |
| `OTA_SSH_USER` | `deploy` |
| `OTA_SSH_PRIVATE_KEY` | полный PEM (включая `BEGIN`/`END`) |
| `OTA_DEPLOY_DIR` | `/var/www/ota` |
| `OTA_PUBLIC_APK_URL` | `https://app.example.com/city_app.apk` |

**На сервере** пользователь `deploy` с ключом из CI должен иметь `scp`/`ssh` в `OTA_DEPLOY_DIR`.

После `git push` в `main` (или `workflow_dispatch`) — сборка, SHA-256, копирование `city_app.apk`, перезапись `version.json`.

**Важно:** перед релизом увеличьте `version: x.y.z+N` в `pubspec.yaml` (число после `+` = новый `version_code`).

## Поведение в приложении

- Стартовая проверка: `lib/main.dart` → `checkForAppUpdates` (как и раньше).
- **Android** + `UPDATE_MANIFEST_URL` — полный сценарий (диалог, прогресс, установщик).
- **Иначе** (iOS, нет `UPDATE_MANIFEST_URL`) — fallback на Supabase-таблицу `app_config` (ссылка «скачать в браузере»), как раньше.

## Диагностика

- OTA-ошибки валидации манифеста — в debug в консоль; не блокируют запуск.
- Ошибка SHA — пользователю в диалоге, установка отменена.
- `open file` / установщик — кнопка «Настройки приложения» (разрешение на установку неизвестных пакетов / источник).
