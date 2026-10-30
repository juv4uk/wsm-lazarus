#!/usr/bin/env bash
# G6.250 — індекс verified-профілів не має розходитися з кодом.
#
# Перегенеровуємо індекс у тимчасовий файл і порівнюємо з закоміченим.
# Розбіжність = хтось додав/прибрав модуль і не оновив індекс.
set -uo pipefail
cd "$(dirname "$0")/.."

DOC=docs/verified-profiles.uk.md
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

[ -f "$DOC" ] || { echo "VERIFIED-INDEX-FAIL немає $DOC" >&2; exit 1; }
bash scripts/gen-verified-index.sh "$TMP" >/dev/null

if ! diff -q "$DOC" "$TMP" >/dev/null; then
  echo "VERIFIED-INDEX-FAIL $DOC розійшовся з кодом:" >&2
  diff -u "$DOC" "$TMP" | head -30 >&2
  echo "виправлення: bash scripts/gen-verified-index.sh" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=індекс verified::docs/verified-profiles.uk.md застарів — виконайте scripts/gen-verified-index.sh" >&2
  fi
  exit 1
fi
echo "VERIFIED-INDEX-PASS"
