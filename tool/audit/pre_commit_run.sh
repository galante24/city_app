#!/usr/bin/env bash
# Production pre-commit (главная точка входа через .githooks/pre-commit)
# 1 SECURITY 2 AUTO-FIX (format + opt dart fix) 3 bad code 4 analyze 5 tests (opt)
# 6 perf warn 7 version bump 8 debug APK 9 summary log
# См. docs/git-hooks.md — AUTO_PUSH, SKIP_*, PRE_COMMIT_DART_FIX, PRE_COMMIT_FLUTTER_TEST
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

if [ "${GIT_HOOK_AUTO_ADD:-0}" = "1" ] || [ "${GIT_HOOK_AUTO_ADD:-}" = "true" ]; then
  echo "pre_commit_run: GIT_HOOK_AUTO_ADD=1 — git add -A" >&2
  git add -A
fi

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

if ! git diff --cached --name-only 2>/dev/null | grep -q .; then
  echo "pre_commit_run: нет staged файлов — коммит отмените или добавьте файлы (git add)" >&2
  exit 0
fi

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

# --- 1) SECURITY (blocking)
bash "$AUDIT_DIR/security_scan.sh" || exit 1

# --- 2) AUTO FIX: format staged; опционально dart fix --apply (PRE_COMMIT_DART_FIX=1 / DART_FIX_APPLY=1)
if [ "${PRE_COMMIT_DART_FIX:-0}" = "1" ] || [ "${PRE_COMMIT_DART_FIX:-}" = "true" ]; then
  export DART_FIX_APPLY=1
fi
bash "$AUDIT_DIR/quality_dart.sh" || exit 1

# --- 3) Block print / debugPrint / TODO / FIXME in added lines
bash "$AUDIT_DIR/bad_dart_staged.sh" || exit 1

# --- 4) ANALYZE (blocking)
if [ "${SKIP_FLUTTER_ANALYZE:-0}" != "1" ]; then
  echo "pre_commit_run: flutter pub get…" >&2
  flutter pub get
  echo "pre_commit_run: flutter analyze (обязательно)…" >&2
  flutter analyze
else
  echo "pre_commit_run: SKIP_FLUTTER_ANALYZE" >&2
fi

# --- 5) TEST (optional)
if [ "${PRE_COMMIT_FLUTTER_TEST:-0}" = "1" ] || [ "${PRE_COMMIT_FLUTTER_TEST:-}" = "true" ]; then
  if [ "${SKIP_FLUTTER_TEST:-0}" = "1" ]; then
    echo "pre_commit_run: SKIP_FLUTTER_TEST" >&2
  elif [ -d test ] && [ -n "$(find test -name '*_test.dart' -print -quit 2>/dev/null || true)" ]; then
    echo "pre_commit_run: PRE_COMMIT_FLUTTER_TEST=1 — flutter test…" >&2
    flutter test || exit 1
  else
    echo "pre_commit_run: нет test/*_test.dart — flutter test пропущен" >&2
  fi
else
  echo "pre_commit_run: flutter test пропущен (PRE_COMMIT_FLUTTER_TEST=1 для включения)" >&2
fi

# --- 6) Performance (не блокирует)
if [ "${SKIP_PERFORMANCE_WARN:-0}" != "1" ]; then
  bash "$AUDIT_DIR/performance_warn.sh" || true
fi

# --- 7) VERSION BUMP
BUMPED_VER=""
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
    BUMPED_VER="$(bash "$REPO_ROOT/tool/version_bump.sh" pubspec.yaml 2>&1 | tail -n 1 || true)"
    git add pubspec.yaml
  else
    echo "pre_commit_run: bump пропущен" >&2
  fi
fi

# --- 8) Local debug APK (обязателен)
APK_PATH=""
if [ "${SKIP_LOCAL_DEBUG_APK:-0}" = "1" ]; then
  echo "pre_commit_run: SKIP_LOCAL_DEBUG_APK=1 — debug APK пропущен" >&2
else
  bash "$REPO_ROOT/tool/local_apk_debug_build.sh" || exit 1
  VER_LINE="$(grep -E '^version:' pubspec.yaml | head -1 | sed 's/^version:[[:space:]]*//;s/[[:space:]]#.*$//;s/[[:space:]]*$//;s/\r$//')"
  CODE="${VER_LINE#*+}"
  if [ -n "$CODE" ] && [ "$CODE" != "$VER_LINE" ]; then
    APK_PATH="builds/local_apk/app_v${CODE}.apk"
  fi
fi

# --- 9) LOG file + human summary
LOG="$REPO_ROOT/builds/.githook_precommit.log"
mkdir -p "$REPO_ROOT/builds" 2>/dev/null || true
TS="$(date -Iseconds 2>/dev/null || date)"
{
  echo "=== pre_commit_run OK $TS ==="
  echo "staged: $(git diff --cached --name-only 2>/dev/null | tr '\n' ' ')"
  if [ -n "$BUMPED_VER" ]; then
    echo "version bump output: $BUMPED_VER"
  fi
  if [ -n "$APK_PATH" ] && [ -f "$REPO_ROOT/$APK_PATH" ]; then
    echo "apk: $APK_PATH"
  fi
} >>"$LOG" 2>/dev/null || true

VER_DISPLAY="$(grep -E '^version:' pubspec.yaml 2>/dev/null | head -1 | sed 's/^version:[[:space:]]*//;s/[[:space:]]#.*$//;s/\r$//' || echo '?')"
{
  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "✔ checks passed" >&2
  echo "✔ version (pubspec): $VER_DISPLAY" >&2
  if [ -n "$APK_PATH" ] && [ -f "$REPO_ROOT/$APK_PATH" ]; then
    echo "✔ APK: $APK_PATH" >&2
  elif [ "${SKIP_LOCAL_DEBUG_APK:-0}" != "1" ]; then
    echo "✔ APK: собран (см. builds/local_apk/)" >&2
  fi
  echo "→ CI/OTA: после git push (main) — android-ota-deploy. Локальный push: опционально AUTO_PUSH=1" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
} 2>&1

exit 0
