#!/usr/bin/env bash
# Увеличивает только build number (после +) в pubspec.yaml; x.y.z не трогает.
# Требуется: python3
# Usage: version_bump.sh [path/to/pubspec.yaml]
set -euo pipefail

PUBSPEC="${1:-pubspec.yaml}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f "$PUBSPEC" ]]; then
  echo "version_bump: файл не найден: $PUBSPEC" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "version_bump: требуется python3 или python в PATH" >&2
  exit 1
fi

NEW_VER="$("$PYTHON" - "$PUBSPEC" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
raw = path.read_text(encoding="utf-8")
lines = raw.splitlines(keepends=True)
line_re = re.compile(r"^(\s*version:\s*)(\S+)(.*)$")
done = False
out = []

def bump(val: str):
    m = re.fullmatch(r"(\d+\.\d+\.\d+)\+(\d+)", val.strip(), flags=re.IGNORECASE)
    if not m:
        return None
    name, b = m.group(1), int(m.group(2))
    return f"{name}+{b + 1}"

for line in lines:
    if done:
        out.append(line)
        continue
    m = line_re.match(line)
    if not m:
        out.append(line)
        continue
    val = m.group(2)
    newv = bump(val)
    if newv is None:
        print("version_bump: ожидается a.b.c+N, получено:", val, file=sys.stderr)
        sys.exit(1)
    print(f"version: {val.strip()} → {newv}", file=sys.stderr)
    suf = m.group(3) or ""
    out.append(f"{m.group(1)}{newv}{suf}")
    print(newv)
    done = True

if not done:
    print("version_bump: нет подходящей строки version:", file=sys.stderr)
    sys.exit(1)

text = "".join(out)
# newline: сохраняем, если в файле не было \n в конце — лучше добавить завершающий \n для POSIX
if text and not text.endswith("\n"):
    text += "\n"
path.write_text(text, encoding="utf-8")
sys.exit(0)
PY
)"

echo "version_bump: $PUBSPEC -> $NEW_VER"
