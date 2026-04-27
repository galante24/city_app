#!/usr/bin/env bash
# Только bump + git add pubspec (старое поведение pre-commit).
# Активируется при SKIP_PRE_COMMIT_FULL=1
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  exit 0
fi
if [ "${SKIP_VERSION_BUMP:-0}" = "1" ]; then
  exit 0
fi
if ! git diff --cached --name-only | grep -q .; then
  exit 0
fi
STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
ONLY_PUB=1
# shellcheck disable=SC2086
for f in $STAGED; do
  if [ "$f" != "pubspec.yaml" ]; then
    ONLY_PUB=0
    break
  fi
done
[ "$ONLY_PUB" = "1" ] && exit 0

[ -f pubspec.yaml ] || exit 0
bash "$REPO_ROOT/tool/version_bump.sh" pubspec.yaml
git add pubspec.yaml
exit 0
