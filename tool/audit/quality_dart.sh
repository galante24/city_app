#!/usr/bin/env bash
# Форматирование staged .dart; DART_FIX_APPLY=1 — dart fix --apply
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v dart >/dev/null 2>&1; then
  echo "quality_dart: dart не в PATH" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  exit 0
fi

COUNT=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  dart format "$f"
  git add "$f"
  COUNT=$((COUNT + 1))
done <<EOF
$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.dart$' || true)
EOF

if [ "$COUNT" = "0" ]; then
  echo "quality_dart: нет staged .dart" >&2
  exit 0
fi

if [ "${DART_FIX_APPLY:-0}" = "1" ]; then
  echo "quality_dart: dart fix --apply (opt-in)…" >&2
  dart fix --apply || true
  git add -u lib 2>/dev/null || true
fi

echo "quality_dart: OK ($COUNT files)" >&2
exit 0
