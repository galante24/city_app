#!/usr/bin/env bash
# Pre-commit (production-lean): security → (opt. perf) → format → analyze →
# (opt.) test → (opt.) bump → (opt.) debug APK.
# См. docs/git-hooks.md. Отключающие env: SKIP_*; включение тяжёлого: PRE_COMMIT_*=1
set -euo pipefail

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  exit 0
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
export REPO_ROOT
cd "$REPO_ROOT" || exit 0

# Опционально: автоматически проиндексировать всё (осторожно: проверяйте staging)
if [ "${GIT_HOOK_AUTO_ADD:-0}" = "1" ] || [ "${GIT_HOOK_AUTO_ADD:-}" = "true" ]; then
  echo "pre_commit_run: GIT_HOOK_AUTO_ADD=1 — git add -A" >&2
  git add -A
fi

# Слияния / rebase: только лёгкие проверки
if [ -f "$(git rev-parse --git-path MERGE_HEAD 2>/dev/null)" ] 2>/dev/null; then
  echo "pre_commit_run: merge in progress — полный pipeline пропущен" >&2
  exit 0
fi
if [ -f "$(git rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null)" ] 2>/dev/null; then
  echo "pre_commit_run: cherry-pick — пропущен" >&2
  exit 0
fi
if [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] 2>/dev/null || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ] 2>/dev/null; then
  echo "pre_commit_run: rebase — пропущен" >&2
  exit 0
fi

if [ "${SKIP_PRE_COMMIT_FULL:-0}" = "1" ]; then
  echo "pre_commit_run: SKIP_PRE_COMMIT_FULL=1 — только bump" >&2
  exec bash "$REPO_ROOT/tool/audit/bump_only.sh"
fi

# Нет staged — нечего валидировать
if ! git diff --cached --name-only 2>/dev/null | grep -q .; then
  echo "pre_commit_run: нет staged файлов" >&2
  exit 0
fi

# Только pubspec в индексе — ручной релиз версии, не дублировать bump
NO_BUMP=0
CNT=0
ONLY_PUBSPEC=1
while IFS= read -r line; do
  [ -z "$line" ] && continue
  CNT=$((CNT + 1))
  [ "$line" != "pubspec.yaml" ] && ONLY_PUBSPEC=0
done <<EOF
$(git diff --cached --name-only 2>/dev/null || true)
EOF
if [ "$CNT" -eq 1 ] && [ "$ONLY_PUBSPEC" = "1" ]; then
  NO_BUMP=1
  echo "pre_commit_run: в индексе только pubspec.yaml — auto version bump пропущен" >&2
fi

AUDIT_DIR="$REPO_ROOT/tool/audit"
bash "$AUDIT_DIR/security_scan.sh" || exit 1

if [ "${PRE_COMMIT_PERFORMANCE_WARN:-0}" = "1" ] || [ "${PRE_COMMIT_PERFORMANCE_WARN:-}" = "true" ]; then
  bash "$AUDIT_DIR/performance_warn.sh" || true
fi

bash "$AUDIT_DIR/quality_dart.sh" || exit 1

# --- Статика
if [ "${SKIP_FLUTTER_ANALYZE:-0}" != "1" ]; then
  echo "pre_commit_run: flutter pub get…" >&2
  flutter pub get
  echo "pre_commit_run: flutter analyze (обязательно)…" >&2
  flutter analyze
else
  echo "pre_commit_run: SKIP_FLUTTER_ANALYZE" >&2
fi

# Тесты: только по opt-in (CI — основной прогон)
if [ "${PRE_COMMIT_FLUTTER_TEST:-0}" = "1" ] || [ "${PRE_COMMIT_FLUTTER_TEST:-}" = "true" ]; then
  if [ "${SKIP_FLUTTER_TEST:-0}" = "1" ]; then
    echo "pre_commit_run: SKIP_FLUTTER_TEST — пропуск" >&2
  elif [ -d test ] && [ -n "$(find test -name '*_test.dart' -print -quit 2>/dev/null || true)" ]; then
    echo "pre_commit_run: PRE_COMMIT_FLUTTER_TEST=1 — flutter test…" >&2
    flutter test || exit 1
  fi
else
  echo "pre_commit_run: flutter test пропущен (лёгкий pre-commit; opt-in: PRE_COMMIT_FLUTTER_TEST=1)" >&2
fi

if [ "${SKIP_VERSION_BUMP:-0}" = "1" ] || [ "$NO_BUMP" = "1" ]; then
  if [ "$NO_BUMP" = "0" ]; then
    echo "pre_commit_run: без version bump" >&2
  fi
else
  STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
  ONLY_PUB=1
  for f in $STAGED; do
    if [ "$f" != "pubspec.yaml" ]; then
      ONLY_PUB=0
      break
    fi
  done
  if [ "$ONLY_PUB" = "0" ] && [ -f pubspec.yaml ]; then
    if command -v bash >/dev/null 2>&1; then
      bash "$REPO_ROOT/tool/version_bump.sh" pubspec.yaml
      git add pubspec.yaml
    fi
  else
    echo "pre_commit_run: bump пропущен" >&2
  fi
fi

# Debug APK: только по opt-in; release — в CI
if [ "${PRE_COMMIT_DEBUG_APK:-0}" = "1" ] || [ "${PRE_COMMIT_DEBUG_APK:-}" = "true" ]; then
  if [ "${SKIP_LOCAL_DEBUG_APK:-0}" = "1" ]; then
    echo "pre_commit_run: SKIP_LOCAL_DEBUG_APK — debug APK пропущен" >&2
  else
    bash "$REPO_ROOT/tool/local_apk_debug_build.sh" || exit 1
  fi
else
  echo "pre_commit_run: debug APK пропущен (opt-in: PRE_COMMIT_DEBUG_APK=1; release в CI)" >&2
fi

LOG="$REPO_ROOT/builds/.githook_precommit.log"
mkdir -p "$REPO_ROOT/builds" 2>/dev/null || true
{
  echo "=== pre_commit_run OK $(date -Iseconds 2>/dev/null || date) ==="
} >> "$LOG" 2>/dev/null || true

echo "pre_commit_run: OK" >&2
exit 0
