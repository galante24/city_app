#!/usr/bin/env bash
# Debug APK в builds/local_apk/app_v<version_code>.apk; при ошибке — exit 1.
# Может занять несколько минут. Отключение: SKIP_LOCAL_DEBUG_APK=1
set -euo pipefail

if [ -n "${SKIP_LOCAL_DEBUG_APK:-}" ] && [ "${SKIP_LOCAL_DEBUG_APK}" != "0" ]; then
  echo "local_apk_debug: пропущен (SKIP_LOCAL_DEBUG_APK)" >&2
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "local_apk_debug: flutter не в PATH" >&2
  exit 1
fi

PUB="pubspec.yaml"
if [ ! -f "$PUB" ]; then
  echo "local_apk_debug: нет $PUB" >&2
  exit 1
fi

VER_LINE="$(grep -E '^version:[[:space:]]*' "$PUB" | head -1)"
VER_FULL="$(printf '%s' "$VER_LINE" | sed 's/^version:[[:space:]]*//;s/[[:space:]]#.*$//;s/[[:space:]]*$//;s/\r$//')"
CODE="${VER_FULL#*+}"
if [ -z "$CODE" ] || [ "$CODE" = "$VER_FULL" ]; then
  echo "local_apk_debug: ожидается a.b.c+N в pubspec" >&2
  exit 1
fi

echo "local_apk_debug: flutter build apk --debug" >&2
flutter build apk --debug

APK_BUILT="build/app/outputs/flutter-apk/app-debug.apk"
if [ ! -f "$APK_BUILT" ] || [ ! -s "$APK_BUILT" ]; then
  echo "local_apk_debug: нет $APK_BUILT после сборки" >&2
  exit 1
fi

OUT_DIR="builds/local_apk"
mkdir -p "$OUT_DIR"
OUT="${OUT_DIR}/app_v${CODE}.apk"
cp -f "$APK_BUILT" "$OUT"
echo "local_apk_debug: сохранено $OUT ($({ wc -c < "$OUT" | tr -d ' '; }) bytes)" >&2
exit 0
