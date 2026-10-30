#!/usr/bin/env bash
# Точне D12+ множення: фізичний позитив/негатив + незалежний SENS REPL oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'МНОЖЕННЯ-БЛОК: немає Free Pascal' >&2; exit 127; }
bash ./scripts/test-numericplane.sh
mkdir -p build/m0.2/numericmul-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/numericmul-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-numericmul "$ROOT/scripts/test-numericmul.pas"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/numericmul-units" -FE"$ROOT/build/m0.2/bin" \
  -osenschyslopomnozhyty "$ROOT/src/senschyslopomnozhyty.lpr"
"$ROOT/build/m0.2/bin/test-numericmul"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
clean_heap_report() {
  local report="$1"
  if [[ ! -s "$report" ]]; then return 0; fi
  if grep -Fq '0 unfreed memory blocks : 0' "$report" &&
      ! grep -Fq 'ПОМИЛКА:' "$report"; then return 0; fi
  echo 'МНОЖЕННЯ-ПРОВАЛ: HeapTrc не підтвердив чисте завершення' >&2
  cat "$report" >&2
  exit 1
}
printf '%s\n' '2047' > "$TMP/ліве.lisp"
printf '%s\n' '2' > "$TMP/праве.lisp"
"$ROOT/build/m0.2/bin/senschyslo" --з-укр D12 "$TMP/ліве.lisp" "$TMP/ліве.sens"
"$ROOT/build/m0.2/bin/senschyslo" --з-укр D12 "$TMP/праве.lisp" "$TMP/праве.sens"
"$ROOT/build/m0.2/bin/senschyslopomnozhyty" D12 "$TMP/ліве.sens" "$TMP/праве.sens" \
  > "$TMP/добуток.sens" 2>"$TMP/успіх.err"
clean_heap_report "$TMP/успіх.err"
printf '%s\n' '4094' > "$TMP/очікуване.lisp"
"$ROOT/build/m0.2/bin/senschyslo" --з-укр D24 \
  "$TMP/очікуване.lisp" "$TMP/очікуване.sens"
cmp "$TMP/очікуване.sens" "$TMP/добуток.sens"
"$ROOT/build/m0.2/bin/senschyslo" --в-укр D24 "$TMP/добуток.sens" \
  > "$TMP/проєкція.lisp"
cmp "$TMP/очікуване.lisp" "$TMP/проєкція.lisp"

negative() {
  local label="$1";shift
  if "$ROOT/build/m0.2/bin/senschyslopomnozhyty" "$@" \
    >"$TMP/$label.out" 2>"$TMP/$label.err"; then
    echo "МНОЖЕННЯ-ПРОВАЛ: прийнято $label" >&2; exit 1
  fi
  test ! -s "$TMP/$label.out" || {
    echo "МНОЖЕННЯ-ПРОВАЛ: частковий stdout $label" >&2; exit 1
  }
  grep -Fq 'ПОМИЛКА:' "$TMP/$label.err" || {
    cat "$TMP/$label.err" >&2; echo "МНОЖЕННЯ-ПРОВАЛ: не видно помилки $label" >&2; exit 1
  }
}
printf '\363' > "$TMP/поганий.sens"
negative corrupt D12 "$TMP/поганий.sens" "$TMP/праве.sens"
negative projection D12 "$TMP/ліве.lisp" "$TMP/праве.sens"
negative unknown D10 "$TMP/ліве.sens" "$TMP/праве.sens"
negative missing D12 "$TMP/відсутній.sens" "$TMP/праве.sens"
negative mismatch D24 "$TMP/ліве.sens" "$TMP/праве.sens"
"$ROOT/build/m0.2/bin/senschyslopomnozhyty" D12 \
  "$TMP/ліве.sens" "$TMP/праве.sens" >"$TMP/повтор.sens" 2>"$TMP/повтор.err"
cmp "$TMP/очікуване.sens" "$TMP/повтор.sens"
echo 'NUMERIC-MUL-CLI-OK T5M=exact D12-to-D24=yes negative=5 stdout=atomic'

if [[ -v SENS_ORACLE_BIN ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = \
    '2c498b35af53c085450eac6f51b87facf7f9aa47'
  for entry in '7|-7|-49' '2047|1|2047' '-2048|-1|2048' '12|12|144'; do
    IFS='|' read -r left right expected <<<"$entry"
    printf '%s\n' "$left" >"$TMP/1.lisp"
    printf '%s\n' "$right" >"$TMP/2.lisp"
    rm -f "$TMP/1.sens" "$TMP/2.sens"
    "$ROOT/build/m0.2/bin/senschyslo" --з-укр D12 "$TMP/1.lisp" "$TMP/1.sens"
    "$ROOT/build/m0.2/bin/senschyslo" --з-укр D12 "$TMP/2.lisp" "$TMP/2.sens"
    "$ROOT/build/m0.2/bin/senschyslopomnozhyty" D12 "$TMP/1.sens" "$TMP/2.sens" \
      > "$TMP/3.sens" 2>"$TMP/3.err"
    if [[ "$expected" == "2048" ]]; then width=D24; else width=D12; fi
    "$ROOT/build/m0.2/bin/senschyslo" --в-укр "$width" "$TMP/3.sens" \
      > "$TMP/native.txt"
    printf '(помножити %s %s)\n' "$left" "$right" > "$TMP/expression.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/expression.lisp" > "$TMP/sens.txt" 2>"$TMP/sens.err"
    printf '%s\n' "$expected" > "$TMP/expected.txt"
    cmp "$TMP/expected.txt" "$TMP/native.txt"
    cmp "$TMP/native.txt" "$TMP/sens.txt" || {
      cat "$TMP/sens.err" >&2; echo 'NUMERIC-MUL-ORACLE-FAIL' >&2; exit 1
    }
  done
  echo 'NUMERIC-MUL-ORACLE-OK pinned-SENS=exact signed=D12 widening=D24 samples=4'
fi
