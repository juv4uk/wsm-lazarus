#!/usr/bin/env bash
# G6.171 — фізичний pinned Core1 → 8 конкурентних компіляцій і 87 ELF запусків.
# Ніяких законів у Python: лише процеси, SHA, точні T5M і незалежний oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo "потрібен Linux x86-64" >&2; exit 127; }
for t in git fpc timeout python3 mktemp readelf grep; do
  command -v "$t" >/dev/null || { echo "відсутня утиліта $t" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test -s external/sens/lib/core1.sens
grep -Fq "(визначити ядро1-додати" external/sens/lib/core1.lisp
grep -Fq "(визначити ядро1-відняти" external/sens/lib/core1.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.build "$TMP"/*.err; do if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 35 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/u" "$TMP/fixtures" "$TMP/work"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$TMP/u" -FE"$TMP/bin" -otest-core1potik-fixtures \
  "$ROOT/scripts/test-core1potik-fixtures.pas" >"$TMP/fixtures.build" 2>&1
timeout 40s "$TMP/bin/test-core1potik-fixtures" "$TMP/fixtures" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
test ! -s "$TMP/fixtures.err"
grep -Fq "total=40 d12=33 d24=7 bad=7" "$TMP/fixtures.out"
test "$(wc -l < "$TMP/fixtures/cases.tsv")" -eq 33
test "$(wc -l < "$TMP/fixtures/promotion.tsv")" -eq 7
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  timeout 1500s python3 scripts/test-core1-potiky-paralel.py oracle \
    "$ROOT" "$SENS_ORACLE_BIN" "$TMP/fixtures" "$TMP/work"
else
  timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/u" -FE"$TMP/bin" -osenscore1potikelf \
    "$ROOT/src/senscore1potikelf.lpr" >"$TMP/compiler.build" 2>&1
  test -x "$TMP/bin/senscore1potikelf"
  timeout 750s python3 scripts/test-core1-potiky-paralel.py native \
    "$ROOT" "$TMP/bin/senscore1potikelf" "$TMP/fixtures" "$TMP/work"
fi
