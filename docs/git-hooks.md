# Git hooks, локальный pre-commit pipeline, CI/Secrets

## Цель

Один раз настроив `core.hooksPath=.githooks`, на каждый **`git commit`** (по умолчанию) запускается **лёгкий** pipeline: **security → `dart format` (staged) → `flutter analyze` → (opt.) `flutter test` → (opt.) bump `+build` → (opt.) debug APK**.

Тяжёлые вещи **по умолчанию отключены**: `flutter test` и локальная debug APK — в CI на `main` (см. ниже). Включение: `PRE_COMMIT_FLUTTER_TEST=1`, `PRE_COMMIT_DEBUG_APK=1`.

После успешного коммита **`post-commit`** пытается **`git push`** (если есть `upstream`).

`push` → GitHub: **[`.github/workflows/android-ota-deploy.yml`](../.github/workflows/android-ota-deploy.yml)** — (опц.) `supabase db push` **только** при repository variable **`MIGRATION_APPROVED=1`**, затем analyze, **release** APK, деплой на VPS и `version.json` (OTA). Приложение: `VpsOtaService`, `lib/config/app_secrets.dart`.

**Отдельный** workflow [`.github/workflows/release.yml`](../.github/workflows/release.yml) — **GitHub Release + Supabase `app_config`**: запускается **вручную** (`workflow_dispatch`) или **при push тега** `v*` (нет дублирования с каждым push в `main`).

---

## 1) Первичная настройка (один раз)

Из **корня** репозитория `city_app/`:

```bash
git config core.hooksPath .githooks
bash tool/setup-git-hooks.sh
# Windows: Git Bash обязателен для pre-commit (bash + sh hooks)
```

Проверка:

```bash
git config --get core.hooksPath
# .githooks
```

Опционально: установите [gitleaks](https://github.com/gitleaks/gitleaks) в PATH (жёсткий скан секретов) и/или [ripgrep](https://github.com/BurntSushi/ripgrep) (ускорение аудита).

```bash
# пример: macOS
brew install gitleaks ripgrep
```

---

## 2) Поведение `pre-commit` (порядок)

| Шаг | Скрипт / команда | Блокировка |
|-----|------------------|------------|
| 1 | [`tool/audit/security_scan.sh`](../tool/audit/security_scan.sh) | да |
| 2 (opt) | [`tool/audit/performance_warn.sh`](../tool/audit/performance_warn.sh) | нет, только при `PRE_COMMIT_PERFORMANCE_WARN=1` |
| 3 | [`tool/audit/quality_dart.sh`](../tool/audit/quality_dart.sh) (`dart format` на staged `*.dart`) | да (если format упал) |
| 4 | `flutter pub get` + `flutter analyze` | да |
| 5 (opt) | `flutter test` | только при `PRE_COMMIT_FLUTTER_TEST=1` |
| 6 | [`tool/version_bump.sh`](../tool/version_bump.sh) (только `+build`) + `git add pubspec.yaml` | — (см. исключения) |
| 7 (opt) | [`tool/local_apk_debug_build.sh`](../tool/local_apk_debug_build.sh) | только при `PRE_COMMIT_DEBUG_APK=1` |

- **Debug APK** по умолчанию **не** собирается. Release — в **CI** (`android-ota-deploy`).

- **Тесты** в pre-commit **по умолчанию** не гоняются; основной прогон — CI или `PRE_COMMIT_FLUTTER_TEST=1` локально.

- В индексе **только** `pubspec.yaml` (ручной бамп) — **автоматический** bump **не** выполняется; остальные шаги — да (если не отключены).

### Переменные отключения (только по необходимости)

| Переменная | Эффект |
|------------|--------|
| `SKIP_PRE_COMMIT_FULL=1` | Только `tool/audit/bump_only.sh` (как раньше: bump + add pubspec) |
| `SKIP_SECURITY_SCAN=1` | Не запускать security |
| `SKIP_FLUTTER_ANALYZE=1` | Пропустить `flutter analyze` (нежелательно) |
| `PRE_COMMIT_FLUTTER_TEST=1` | Запустить `flutter test` (если есть `*_test.dart`) |
| `SKIP_FLUTTER_TEST=1` | Не гонять тесты, даже при `PRE_COMMIT_FLUTTER_TEST=1` |
| `SKIP_VERSION_BUMP=1` | Не бампить `version` |
| `PRE_COMMIT_DEBUG_APK=1` | Собрать debug APK (иначе **не** собирать) |
| `SKIP_LOCAL_DEBUG_APK=1` | Не собирать debug APK даже при `PRE_COMMIT_DEBUG_APK=1` |
| `PRE_COMMIT_PERFORMANCE_WARN=1` | Включить `performance_warn.sh` |
| `GIT_HOOK_AUTO_ADD=1` | Перед проверками выполнить `git add -A` (осторожно: смотрите staging) |
| `GIT_HOOK_NO_PUSH=1` | `post-commit` не делает `git push` |
| `PRE_PUSH_DO_RELEASE_APK=1` | `pre-push` вызывает `tool/local_apk_build_and_save.sh` (release в `builds/`) — по умолчанию pre-push **лёгкий** (см. ниже) |

### `pre-push`

По умолчанию **не** дублирует тяжёлую release-сборку (уже есть: debug в pre-commit, release в **CI**).  
Локальная **release** перед push: `PRE_PUSH_DO_RELEASE_APK=1` (и при необходимости не ставить `SKIP_LOCAL_APK_BUILD` в старом смысле; скрипт — [`tool/local_apk_build_and_save.sh`](../tool/local_apk_build_and_save.sh)).

### `prepare-commit-msg`

Пустой текст коммита → от первого файла: `auto: safe update <file> (+N files)`.

### Логи

- `builds/.githook_precommit.log` — успешные прогоны pre-commit pipeline.  
- `builds/.githook_postcommit.log` — попытки `git push` из `post-commit`.

---

## 3) GitHub Actions: `android-ota-deploy.yml`

Триггер: **`push` в `main`**, `workflow_dispatch`.

1. **Supabase** — `supabase db push` **только** если **repository variable** `MIGRATION_APPROVED` = `1` (и заданы `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` и т.д.). Иначе шаг пропущен, сборка **продолжается**.  
2. `flutter pub get` → `flutter analyze`  
3. `flutter build apk --release`  
4. SHA-256; при OTA SSH — **бэкап** прежних `city_app.apk` и `version.json` в `*.prev` на сервере, затем `scp` APK и запись `version.json`.

**Запрет** деплоя при ошибке миграций: при `MIGRATION_APPROVED=1` падает `db push` → job красный, до APK/OTA шаги **не** выполняются.

**Откат на VPS (вручную):** в каталоге OTA:  
`cp city_app.apk.prev city_app.apk` и `cp version.json.prev version.json` (и перезагрузка nginx/кэш при необходимости). Файлы `.prev` создаёт CI перед новым деплоем.

### `MIGRATION_APPROVED` (Repository variables)

| Variable | Значение | Эффект |
|----------|----------|--------|
| `MIGRATION_APPROVED` | `1` | Выполнить `supabase db push` в начале job (нужны Secrets Supabase) |
| не задано / другое | — | Миграции **не** применяются; только build + OTA |

---

## 4) Список GitHub Secrets (рекомендуемые имена)

### Supabase (CI миграции)

**Переменная:** `MIGRATION_APPROVED=1` (см. раздел 3) — **не** Secret.

| Secret | Назначение |
|--------|------------|
| `SUPABASE_ACCESS_TOKEN` | Personal access token (dashboard → Account → Access Tokens) для CLI |
| `SUPABASE_PROJECT_REF` | ref проекта (Project Settings → General) |
| `SUPABASE_DB_PASSWORD` | опционально, если `supabase link` запрашивает пароль БД |

### OTA / VPS (Timeweb)

| Secret | Назначение |
|--------|------------|
| `OTA_SSH_PRIVATE_KEY` | приватный ключ SSH (полный PEM, `-----BEGIN ...`) |
| `OTA_SSH_HOST` | хост, например `vps.example.com` |
| `OTA_SSH_USER` | пользователь (например `deploy` или `root`) |
| `OTA_DEPLOY_DIR` | каталог на сервере, например `/var/www/ota` (оба: APK + `version.json`) |
| `OTA_PUBLIC_APK_URL` | публичный **HTTPS** URL к `city_app.apk` (как в манифесте для телефонов) |

### Подпись release APK (опционально)

| Secret | Назначение |
|--------|------------|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 your.keystore` |
| `KEYSTORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS` | как в `key.properties` |

> Ключи и `.env` **никогда** не в git — только Secrets и артефакты CI. Клиент **без** `service_role` (проверяет `security_scan`).

### Прочие (см. `release.yml` для GitHub Release + `app_config`)

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` — только **на стороне CI** (`release.yml`), не в приложении.

### Мониторинг (Sentry)

- **Flutter:** при сборке/запуске задать `SENTRY_DSN` (`--dart-define` или `api_keys.json`). Пусто — Sentry **не** инициализируется.  
- **chat-api (Nest):** переменная окружения `SENTRY_DSN` в `.env` / systemd / Docker. Пусто — Sentry **не** инициализируется.

## 5) Структура `supabase/migrations/`

SQL-миграции в **`city_app/supabase/migrations/`** (нумерованные `*.sql` + `config.toml`).  
CI: `supabase db push` применяет **неприменённые** миграции **только** при `MIGRATION_APPROVED=1` в репозитории.  
Локально: `cd city_app && supabase db push` (после `supabase link`).

---

## 6) OTA в приложении

- URL манифеста: `UPDATE_MANIFEST_URL` / `kUpdateManifestUrl` (см. `lib/config/app_secrets.dart`).  
- Сервис: `VpsOtaService` — HTTPS, `version_code`, `sha256` (в prod **рекомендуется**), политика хоста, `force` / `min_version_code` (см. `OtaForcePolicy`).

CI генерирует `version.json` в формате, совместимом с `OtaUpdateManifest` (поле `force` по умолчанию `false`; для жёсткого обновления — править JSON на VPS вручную при необходимости).

---

## 7) Ручные команды (без hook)

```bash
bash tool/audit/security_scan.sh
bash tool/local_apk_debug_build.sh
bash tool/local_apk_build_and_save.sh
```

---

## 8) Моделирование сценариев

| Сценарий | Ожидание |
|----------|----------|
| Миграции с `MIGRATION_APPROVED≠1` | `db push` **не** выполняется; build и OTA **идут** |
| Миграции с `MIGRATION_APPROVED=1` и ошибка `db push` | CI **красный**, APK/OTA **не** обновляются |
| Ошибка `flutter analyze` | fail, коммит отменяется |
| Утечка в staging | `security_scan` / gitleaks → **fail** → commit **не** создаётся (если хук до `git commit` завершения — помните: хук `pre-commit` **до** записи commit; при `exit 1` коммит **отменяется) |
| Нет OTA secret | в CI: APK собран, шаг deploy — notice и exit 0 |
| Без `upstream` | `post-commit` печатает подсказку `git push -u` |

*Примечание: если вы вызывали `git commit --no-verify`, хуки обходятся — не используйте для прод-ветки.*
