#!/usr/bin/env bash
# Блок: в добавленных строках staged-диффа нет print(, debugPrint(, литерала TODO
# (только +строки; правки в существующем коде не требуют чистить весь файл).
# Аварийный обход: SKIP_STAGED_DART_LINT=1
set -euo pipefail

if [ "${SKIP_STAGED_DART_LINT:-0}" = "1" ] || [ "${SKIP_STAGED_DART_LINT:-}" = "true" ]; then
  echo "bad_dart_staged: пропущен (SKIP_STAGED_DART_LINT)" >&2
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 0

# Нет .dart в индексе
if ! git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.dart$' -q; then
  exit 0
fi

# Дифф: только реальные добавленные строки (не +++ b/...)
HIT="$(
  git diff --cached -U0 -- '*.dart' 2>/dev/null \
    | awk '/^\+/ && $0 !~ /^\+{3} / { sub(/^\+/, ""); print }' \
    | grep -E '\bprint\s*\(|\bdebugPrint\s*\(|\bTODO\b' || true
)"

if [ -n "$HIT" ]; then
  echo "bad_dart_staged FAIL: в новых/изменённых строках не допускаются print(, debugPrint(, TODO" >&2
  echo "Фрагменты:" >&2
  echo "$HIT" | head -n 20 >&2
  echo "… (см. git diff --cached) — исправьте или SKIP_STAGED_DART_LINT=1 (только в крайнем случае)" >&2
  exit 1
fi

echo "bad_dart_staged: OK" >&2
exit 0
