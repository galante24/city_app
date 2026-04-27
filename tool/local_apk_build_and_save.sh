#!/usr/bin/env bash
# Локальная release-сборка APK и копия в builds/app_v{version}.apk, ротация 10 файлов.
# Использование: из корня Flutter-проекта (где pubspec.yaml).
# Отключение: SKIP_LOCAL_APK_BUILD=1
set -euo pipefail

if [ -n "${SKIP_LOCAL_APK_BUILD:-}" ] && [ "${SKIP_LOCAL_APK_BUILD}" != "0" ]; then
  echo "local_apk: SKIP_LOCAL_APK_BUILD, выход" >&2
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUB="pubspec.yaml"
if [ ! -f "$PUB" ]; then
  echo "local_apk: нет $PUB" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "local_apk: команда flutter не найдена в PATH" >&2
  exit 1
fi

echo "local_apk: flutter build apk --release"
flutter build apk --release

APK_BUILT="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_BUILT" ]; then
  echo "local_apk: не найден $APK_BUILT после сборки" >&2
  exit 1
fi
# размер > 0
if [ ! -s "$APK_BUILT" ]; then
  echo "local_apk: пустой артефакт: $APK_BUILT" >&2
  exit 1
fi

VER_LINE="$(grep -E '^version:[[:space:]]*' "$PUB" | head -1)"
VER="$(printf '%s' "$VER_LINE" | sed 's/^version:[[:space:]]*//;s/[[:space:]]#.*$//;s/[[:space:]]*$//;s/\r$//')"
if [ -z "$VER" ]; then
  echo "local_apk: не удалось прочитать version из $PUB" >&2
  exit 1
fi
case "$VER" in
  *+*) ;;
  *)
    echo "local_apk: ожидается version a.b.c+N, получено: $VER" >&2
    exit 1
    ;;
esac

mkdir -p builds
OUT="builds/app_v${VER}.apk"
cp -f "$APK_BUILT" "$OUT"

if [ ! -f "$OUT" ] || [ ! -s "$OUT" ]; then
  echo "local_apk: копия невалидна: $OUT" >&2
  exit 1
fi

echo "local_apk: сохранено: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"

# копия pubspec для «backup»-следа (не в git, см. .gitignore)
cp -f "$PUB" "builds/.last_built_from_pubspec.yaml" 2>/dev/null || true

# оставить не более 10 app_v*.apk (по времени, старые удалить)
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import os
from pathlib import Path
root = Path("builds")
if not root.is_dir():
    raise SystemExit(0)
files = sorted(
    (p for p in root.iterdir() if p.is_file() and p.suffix == ".apk" and p.name.startswith("app_v")),
    key=lambda p: p.stat().st_mtime,
    reverse=True,
)
for p in files[10:]:
    try:
        p.unlink()
        print("local_apk: удалён старый:", p.name)
    except OSError as e:
        print("local_apk: не удалось удалить", p, e, file=__import__("sys").stderr)
PY
elif command -v python >/dev/null 2>&1; then
  python - <<'PY'
import os
from pathlib import Path
root = Path("builds")
if not root.is_dir():
    raise SystemExit(0)
files = sorted(
    (p for p in root.iterdir() if p.is_file() and p.suffix == ".apk" and p.name.startswith("app_v")),
    key=lambda p: p.stat().st_mtime,
    reverse=True,
)
for p in files[10:]:
    try:
        p.unlink()
        print("local_apk: удалён старый:", p.name)
    except OSError as e:
        print("local_apk: не удалось удалить", p, e, file=__import__("sys").stderr)
PY
else
  echo "local_apk: предупреждение: нет python — ротация 10 APK пропущена" >&2
fi

exit 0
