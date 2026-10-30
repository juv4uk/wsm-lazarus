#!/usr/bin/env bash
# G6.205 — реальний FPC та Linux x86-64 збереження потокового IMUL.
# Одна перевірка pinned D5:10110 WideIR, не окрема мовна семантика.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'Д5-КОНТЕКСТ-ПОТІК-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in fpc timeout cmp mktemp chmod; do
  command -v "$tool" >/dev/null || {
    echo "Д5-КОНТЕКСТ-ПОТІК-БЛОК: немає $tool" >&2
    exit 127
  }
done
test -f "$ROOT/external/sens/lib/domains/d5.lisp" || {
  echo 'Д5-КОНТЕКСТ-ПОТІК-БЛОК: немає pinned SENS' >&2
  exit 66
}
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -Fu"$ROOT/src" \
  -FU"$TMP/units" -FE"$TMP/bin" -otest-mulstream-context \
  "$ROOT/scripts/test-mulstream-context.pas"
timeout 120s "$TMP/bin/test-mulstream-context" \
  "$ROOT/external/sens" "$TMP/fixtures"
ELF="$TMP/fixtures/потік.elf"
test -s "$ELF"
chmod 700 "$ELF"
POS=0
for label in positive negative boundary; do
  timeout 5s "$ELF" <"$TMP/fixtures/$label.frame" \
    >"$TMP/actual.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$TMP/fixtures/$label.expected.sens" "$TMP/actual.sens"
  POS=$((POS+1))
done
test "$POS" -eq 3
NEG=0
for label in overflow bad; do
  rc=0
  timeout 5s "$ELF" <"$TMP/fixtures/$label.frame" \
    >"$TMP/rejected.sens" 2>"$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/rejected.sens"
  grep -Fq 'ВІДМОВА' "$TMP/rejected.err"
  NEG=$((NEG+1))
done
test "$NEG" -eq 2
# Після двох відмов повторне виконання ТОГО САМОГО ELF не переносить
# жодного стану (ні compiler context, ні stdin) між процесами.
timeout 5s "$ELF" <"$TMP/fixtures/positive.frame" \
  >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
test ! -s "$TMP/recovery.err"
cmp "$TMP/fixtures/positive.expected.sens" "$TMP/recovery.sens"
echo 'Д5-КОНТЕКСТ-ПОТІК-ГОТОВО proofs=4 byte-equal=yes executed=4 rejects=2 energy=NOT-MEASURED'
