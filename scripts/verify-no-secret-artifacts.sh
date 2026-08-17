#!/bin/sh
set -eu

# This intentionally checks names and high-confidence token shapes only. It is
# a deterministic local guard, not a replacement for gitleaks or review.
if find . -type f \( -name '.env' -o -name '.env.*' -o -name '*access-token*' -o -name '*app-secret*' \) \
  -not -path './.build/*' -print | grep -q .; then
  exit 1
fi

if rg -n --hidden --glob '!/.build/**' --glob '!scripts/verify-no-secret-artifacts.sh' \
  "(?i)(facebook.*access[_-]?token\\s*[:=]\\s*[\\\"']?[A-Za-z0-9_-]{24,}|EAAC[A-Za-z0-9_-]{20,})" \
  .; then
  exit 1
fi
