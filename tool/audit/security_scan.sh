#!/usr/bin/env bash
# Блокирующий аудит безопасности перед commit
set -euo pipefail

if [ "${SKIP_SECURITY_SCAN:-0}" = "1" ] || [ "${SKIP_SECURITY_SCAN:-}" = "true" ]; then
  echo "security_scan: пропущен (SKIP_SECURITY_SCAN)" >&2
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "security_scan FAIL: $*" >&2; exit 1; }

STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
if [ -z "$STAGED" ]; then
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    .env|.env.*|api_keys.json|*.jks|*.keystore|*id_rsa*|id_rsa|*.pem|*.p12|*.pfx)
      fail "запрещён файл в staging: $f"
      ;;
  esac
done <<EOF
$STAGED
EOF

if command -v gitleaks >/dev/null 2>&1; then
  echo "security_scan: gitleaks…" >&2
  gitleaks detect --source . --redact 2>&1 || fail "gitleaks обнаружил утечки (или .gitleaksignore / исключения)"
else
  echo "security_scan: gitleaks не в PATH — эвристики only (установите gitleaks для жёсткого режима)" >&2
fi

# (service_role: блокировка в staged, см. ниже)

# HTTP в app_secrets
if [ -f lib/config/app_secrets.dart ] && command -v rg >/dev/null 2>&1; then
  if rg "http://[^'\"\s\)]+" lib/config/app_secrets.dart 2>/dev/null | grep -vE "localhost|127\.0\.0\.1|example\.com" | head -1 | grep -q .; then
    fail "В app_secrets остался http:// (нужен HTTPS для прод-URL)"
  fi
elif [ -f lib/config/app_secrets.dart ]; then
  if grep -E 'http://' lib/config/app_secrets.dart | grep -vE "localhost|127\.0\.0\.1" | head -1 | grep -q .; then
    fail "В app_secrets остался http://"
  fi
fi

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *.png|*.jpg|*.jpeg|*.ico|*.apk|*.ttf|*.woff) continue ;;
  esac
  if grep -E 'ghp_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}' "$f" 2>/dev/null; then
    fail "в $f похож токен (pattern)"
  fi
done <<EOF
$STAGED
EOF

# Staged: service_role (клиент не должен коммитить)
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *.dart) ;;
    *) continue ;;
  esac
  if command -v rg >/dev/null 2>&1; then
    if rg 'service_role' "$f" 2>/dev/null | head -1 | grep -q .; then
      fail "service_role в staged $f"
    fi
  elif grep -qF 'service_role' "$f" 2>/dev/null; then
    fail "service_role в staged $f"
  fi
done <<EOF
$STAGED
EOF

if [ -d supabase/migrations ] && command -v rg >/dev/null 2>&1; then
  if rg 'USING[[:space:]]*\([[:space:]]*true[[:space:]]*\)' supabase/migrations -g'*.sql' 2>/dev/null | head -1 | grep -q .; then
    echo "security_scan: ВНИМАНИЕ: в migrations встречается USING (true) — проверьте RLS вручную" >&2
  fi
fi

echo "security_scan: OK" >&2
exit 0
