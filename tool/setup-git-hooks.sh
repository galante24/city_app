#!/usr/bin/env bash
# Подключает git hooks из .githooks/ (в корне репозитория).
# Запуск: из корня репо: bash tool/setup-git-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ ! -d .git ]; then
  echo "setup-git-hooks: .git не найден — запустите из корня репозитория" >&2
  exit 1
fi
if [ ! -d .githooks ]; then
  echo "setup-git-hooks: папка .githooks отсутствует" >&2
  exit 1
fi
git config core.hooksPath .githooks
echo "core.hooksPath=.githooks (относительно $ROOT)"
for h in pre-commit pre-push prepare-commit-msg post-commit; do
  f=".githooks/$h"
  if [ -f "$f" ]; then
    if git update-index --chmod=+x -- "$f" 2>/dev/null; then
      :
    else
      chmod +x "$f" 2>/dev/null || true
    fi
  fi
done
for s in tool/audit/*.sh tool/version_bump.sh tool/local_apk_debug_build.sh tool/local_apk_build_and_save.sh; do
  [ -f "$s" ] && chmod +x "$s" 2>/dev/null || true
done
echo "Готово. Проверка: git config --get core.hooksPath"
git config --get core.hooksPath
