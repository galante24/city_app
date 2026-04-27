# Git hooks, pre-commit, CI, push (city_app)

## Цель

После `git config core.hooksPath .githooks` каждый **`git commit`** (без `-m` — см. `prepare-commit-msg`) гоняет **production** pipeline: **security → `dart format` (staged) → опцион. `PRE_COMMIT_DART_FIX=1` / `DART_FIX_APPLY=1` → `dart fix --apply` — блок `print`/`debugPrint`/`TODO`/`FIXME` в новых строках → `flutter analyze` → (opt.) `flutter test` → (не блокирует) `performance_warn` → bump `+build` → `flutter build apk --debug` в `builds/local_apk/`.** В конце — сводка в лог (✔ checks, version, путь к APK) и `builds/.githook_precommit.log`.**

**`post-commit` не делает `git push` по умолчанию.** Push: **`AUTO_PUSH=1`**, в переменных окружения, или (надёжно на **Windows** для cmd/PowerShell) **`git config githook.autoPush 1`**, который выставляет [`tool/release.ps1`](../tool/release.ps1) / [`release.cmd`](../release.cmd) перед релизным коммитом.

`push` в `main` (после ручного/авто `git push` на origin) → **[`android-ota-deploy.yml`](../.github/workflows/android-ota-deploy.yml)** — (опц.) `supabase db push` при **`MIGRATION_APPROVED=1`**, `flutter analyze`, `flutter test` (при `test/*_test.dart`), release APK, OTA на VPS, без смены portable backend / MediaStorage.

**`release.yml`** — GitHub Release: теги `v*` или `workflow_dispatch` (второй путь, не дублирует каждый commit на `main`).

---

## 1) Первичная настройка

Из **корня** репозитория `city_app/`:

```bash
git config core.hooksPath .githooks
bash tool/setup-git-hooks.sh
# Windows: для обычного pre-commit (полный pipeline) — Git Bash + bash. Для сценария **только** «релиз из Windows» — см. release.ps1: bash не требуется.
```

### Production release (одна команда, Windows, без обязательного bash)

- **[`tool/release.ps1`](../tool/release.ps1)** — `commit` (или `commit --allow-empty` если нечего коммитить) + **`git config githook.autoPush 1`** + `AUTO_PUSH=1` + `push` → триггер **GitHub Actions** (тот же pipeline, что и при `git push` в `main`).
- **[`release.cmd`](../release.cmd)** (корень репо) — `release.cmd` или `release.cmd -DryRun` (без side effects).
- Перед `git commit` скрипт создаёт **`.git/release-in-progress`**: [`.githooks/pre-commit`](../.githooks/pre-commit) **пропускает** тяжёлый `pre_commit_run.sh` (аудит, локальный debug APK) — «production release» доверяет **CI**; домашняя разработка по-прежнему через полный pre-commit (bash).
- Логи: `builds/releases/release-*.log` (паттерн `*.log` в `.gitignore`).

```powershell
# из корня city_app (PowerShell)
.\tool\release.ps1
# или
.\release.cmd
```

`githook.autoPush` в `finally` снимается после релиза; `release-in-progress` удаляется, чтобы обычные коммиты снова шли через полный pre-commit.

Проверка hooksPath:

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

## 2) Порядок `pre-commit` ([`pre_commit_run.sh`](../tool/audit/pre_commit_run.sh))

| # | Действие | Блокирует? |
|---|----------|------------|
| 1 | [`security_scan.sh`](../tool/audit/security_scan.sh) (gitleaks if present, токены в staged, `service_role` в staged, app_secrets) | да |
| 2 | `quality_dart.sh` — `dart format` на staged `*.dart`; при `PRE_COMMIT_DART_FIX=1` или `DART_FIX_APPLY=1` — `dart fix --apply` + `git add -u lib` | да |
| 3 | [`bad_dart_staged.sh`](../tool/audit/bad_dart_staged.sh) — в **добавленных** строках diff нет `print(`, `debugPrint(`, `TODO`, `FIXME` | да |
| 4 | `flutter pub get` + `flutter analyze` | да |
| 5 | `flutter test` | только при `PRE_COMMIT_FLUTTER_TEST=1` и `test/*_test.dart` |
| 6 | `performance_warn.sh` | **нет** (по умолчанию включён; `SKIP_PERFORMANCE_WARN=1` — откл.) |
| 7 | `version_bump.sh` — `version: a.b.c+N → …` в stderr | если не только pubspec / не `SKIP` |
| 8 | `local_apk_debug_build.sh` — `builds/local_apk/app_v*.apk` | да (`SKIP_LOCAL_DEBUG_APK=1` — аварийно) |

### Переменные окружения

| Переменная | Эффект |
|------------|--------|
| `SKIP_PRE_COMMIT_FULL=1` | Только `bump_only.sh` |
| `SKIP_SECURITY_SCAN=1` | Пропустить security |
| `SKIP_STAGED_DART_LINT=1` | Пропустить `bad_dart_staged` (только в крайнем случае) |
| `SKIP_FLUTTER_ANALYZE=1` | Пропустить analyze |
| `PRE_COMMIT_FLUTTER_TEST=1` | Включить `flutter test` |
| `PRE_COMMIT_DART_FIX=1` | После `dart format`: `dart fix --apply` (как `DART_FIX_APPLY=1` в `quality_dart.sh`) |
| `SKIP_FLUTTER_TEST=1` | Не тесты при `PRE_COMMIT_FLUTTER_TEST=1` |
| `SKIP_VERSION_BUMP=1` | Без bump |
| `SKIP_LOCAL_DEBUG_APK=1` | Без debug APK (редко) |
| `SKIP_PERFORMANCE_WARN=1` | Не вызывать `performance_warn` |
| `GIT_HOOK_AUTO_ADD=1` | `git add -A` до проверок |
| `AUTO_PUSH=1` | Вместе с commit — после `post-commit` сделать `git push` (нужен upstream) |
| `githook.autoPush` = `1` (локальный `git config`, ставит `tool/release.ps1`) | Тот же эффект, что `AUTO_PUSH=1` в `post-commit` (надёжно в cmd/PowerShell на Windows) |
| `GIT_HOOK_NO_PUSH=1` | Никогда не пушить из hook, даже при `AUTO_PUSH=1` |

### `pre-push`

По умолчанию **не** дублирует тяжёлую release-сборку (уже есть: debug в pre-commit, release в **CI**).  
Локальная **release** перед push: `PRE_PUSH_DO_RELEASE_APK=1` (и при необходимости не ставить `SKIP_LOCAL_APK_BUILD` в старом смысле; скрипт — [`tool/local_apk_build_and_save.sh`](../tool/local_apk_build_and_save.sh)).

### `prepare-commit-msg`

Пустой текст (без `git commit -m`) → **`auto: safe update <первый_файл> (+N files)`** и короткий stat.

### `post-commit` и `AUTO_PUSH=1`

По умолчанию **push не выполняется**; в лог: `Run git push to deploy` (и подсказка `AUTO_PUSH=1 git commit` для авто push).

### Логи

- `builds/.githook_precommit.log` — успешные прогоны pre-commit pipeline.  
- `builds/.githook_postcommit.log` — попытки `git push` из `post-commit`.

---

## 3) GitHub Actions: `android-ota-deploy.yml`

Триггер: **`push` в `main`**, `workflow_dispatch`.

1. **Supabase** — `supabase db push` **только** если **repository variable** `MIGRATION_APPROVED` = `1` (и заданы `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` и т.д.). Иначе шаг пропущен, сборка **продолжается**.  
2. `flutter pub get` → `flutter analyze` → **`flutter test`** (если есть `test/*_test.dart`, иначе notice и пропуск)  
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
