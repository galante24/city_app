#!/usr/bin/env bash
# Неблокирующий отчёт по тяжёлым layout-паттернам
set -euo pipefail
[ "${SKIP_PERF_WARN:-0}" = "1" ] && exit 0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 0
[ -d lib ] || exit 0
if command -v rg >/dev/null 2>&1; then
  C=$(rg -c 'IntrinsicWidth' lib -g'*.dart' 2>/dev/null | head -1 || true)
  if [ -n "$C" ]; then
    echo "perf_warn: IntrinsicWidth (проверьте): $(rg -l 'IntrinsicWidth' lib -g'*.dart' 2>/dev/null | head -3 | tr '\n' ' ')" >&2
  fi
  rg -l 'FutureBuilder' lib -g'*.dart' 2>/dev/null | while read -r f; do
    rg -q 'itemBuilder' "$f" 2>/dev/null && echo "perf_warn: $f — FutureBuilder + список?" >&2
  done
fi
echo "perf_warn: готово" >&2
exit 0
