#!/usr/bin/env bash
# Пример отката OTA на VPS: восстановить предыдущий деплой из *.prev
# (CI копирует city_app.apk → city_app.apk.prev и version.json → version.json.prev перед новым scp)
#
# Скопируйте на сервер, задайте OTA_DIR и выполните:
#   sudo bash rollback_vps.example.sh
set -euo pipefail
OTA_DIR="${OTA_DIR:-/var/www/ota}"
cd "$OTA_DIR" || exit 1
if [ ! -f city_app.apk.prev ] || [ ! -f version.json.prev ]; then
  echo "Нет .prev (первый деплой или бэкап не создавался)" >&2
  exit 1
fi
cp -a city_app.apk.prev city_app.apk
cp -a version.json.prev version.json
echo "OTA откат: восстановлены city_app.apk и version.json из .prev"
exit 0
