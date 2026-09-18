#!/usr/bin/env bash
# check-no-lcl.sh — фізичний firewall core (absorption-defense №1 у AGENTS.md).
# Core НЕ може залежати від LCL/GUI: якщо src/*.pas тисне Forms/Controls/LCL
# або користується Variant/TObject — це compile-правило, а не код-рев'ю.
# Fail-closed: будь-який знахід → exit 1.

set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# 1) Голі юніти з LCL/GUI-простором.
grep -nHEn "^(uses|Uses)[^;]*(Forms|Controls|Lcl)" src/*.pas src/*.lpr 2>/dev/null > "$tmp" || true
if [[ -s "$tmp" ]]; then echo 'NO-LCL-FAIL uses:'; cat "$tmp"; fail=1; fi

# 2) Variant/TObject-подібне у core (коментарні рядки ігноруються:
#    заборона має ловити КОД, а не застереження в документації модуля).
grep -nHEn "\bVariant\b|\bTObject\b|\bTVarRec\b" src/*.pas src/*.lpr 2>/dev/null \
  | grep -vE '^src/[^:]+:[0-9]+:\s*\(\*|^src/[^:]+:[0-9]+:\s*\*|^src/[^:]+:[0-9]+://' > "$tmp" || true
if [[ -s "$tmp" ]]; then echo 'NO-LCL-FAIL banned-types:'; cat "$tmp"; fail=1; fi

# 3) Прямі згадки лексем Forms/Controls як класів у core.
grep -nHEn "\bT?(Form|Control)\b" src/*.pas src/*.lpr 2>/dev/null > "$tmp" || true
if [[ -s "$tmp" ]]; then echo 'NO-LCL-FAIL identifiers:'; cat "$tmp"; fail=1; fi

if [[ $fail -eq 1 ]]; then
  echo 'NO-LCL-FAIL: core залежить від GUI/Variant лексем.'
  exit 1
fi
echo 'NO-LCL-OK: core free of LCL/Variant/TObject.'