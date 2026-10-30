#!/usr/bin/env bash
# G3.38. Реальний checked FPC build плюс фізична CLI перевірка.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null 2>&1 || {
  echo 'ДОДАВАННЯ-БЛОК: Free Pascal відсутній' >&2
  exit 127
}
bash ./scripts/test-numericplane.sh
mkdir -p build/m0.2/numericadd-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/numericadd-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-numericadd \
  "$ROOT/scripts/test-numericadd.pas"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/numericadd-units" \
  -FE"$ROOT/build/m0.2/bin" -osenschyslododaty \
  "$ROOT/src/senschyslododaty.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
clean_heap_report() {
  local report="$1"
  if [[ ! -s "$report" ]]; then return 0; fi
  if grep -Fq '0 unfreed memory blocks : 0' "$report" &&
      ! grep -Fq 'ПОМИЛКА:' "$report"; then return 0; fi
  echo 'ДОДАВАННЯ-ПРОВАЛ: HeapTrc не підтвердив чисте завершення' >&2
  cat "$report" >&2
  exit 1
}
"$ROOT/build/m0.2/bin/test-numericadd" "$TMP" \
  >"$TMP/self.out" 2>"$TMP/self.err"
grep -aFq 'ДОДАВАННЯ-FPC-ГАРАЗД' "$TMP/self.out" || {
  echo 'ДОДАВАННЯ-ПРОВАЛ: FPC самотест не вивів цілий UTF-8 підсумок' >&2
  cat "$TMP/self.out" "$TMP/self.err" >&2
  exit 1
}
"$ROOT/build/m0.2/bin/senschyslododaty" D12 \
  "$TMP/left.sens" "$TMP/right.sens" >"$TMP/result.sens" 2>"$TMP/ok.err"
clean_heap_report "$TMP/ok.err"
if grep -Fq "ПОМИЛКА:" "$TMP/ok.err"; then
  echo "ДОДАВАННЯ-ПРОВАЛ: помилка на позитивному вході" >&2
  exit 1
fi
cmp "$TMP/expected.sens" "$TMP/result.sens"

fail_closed() {
  local label="$1"
  shift
  if "$ROOT/build/m0.2/bin/senschyslododaty" "$@" \
      >"$TMP/$label.out" 2>"$TMP/$label.err"; then
    echo "ДОДАВАННЯ-ПРОВАЛ: прийнято $label" >&2
    exit 1
  fi
  test ! -s "$TMP/$label.out" || {
    echo "ДОДАВАННЯ-ПРОВАЛ: частковий stdout $label" >&2
    exit 1
  }
  grep -Fq 'ПОМИЛКА:' "$TMP/$label.err" || {
    echo "ДОДАВАННЯ-ПРОВАЛ: немає діагностики $label" >&2
    exit 1
  }
}
fail_closed mixed D12 "$TMP/left.sens" "$TMP/wrong.sens"
fail_closed corrupt D12 "$TMP/left.sens" "$TMP/bad.sens"
fail_closed projection D12 "$TMP/human.lisp" "$TMP/right.sens"
fail_closed unknown D10 "$TMP/left.sens" "$TMP/right.sens"
fail_closed missing D12 "$TMP/missing.sens" "$TMP/right.sens"
"$ROOT/build/m0.2/bin/senschyslododaty" D12 \
  "$TMP/left.sens" "$TMP/right.sens" >"$TMP/recovery.sens"
cmp "$TMP/expected.sens" "$TMP/recovery.sens"
echo 'ДОДАВАННЯ-CLI-ГАРАЗД фізичні-байти=точні D12-у-D24=так відмови=5 stdout=атомарний'

# Лише якщо явно задано незалежний pinned SENS REPL.
# Локальна гілка без oracle — механічні тести, не семантичний доказ.
if [[ -v SENS_ORACLE_BIN ]]; then
  command -v timeout >/dev/null
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = \
    '2c498b35af53c085450eac6f51b87facf7f9aa47'
  for example in '7|-7|12|0' '2047|1|24|2048' \
      '-2048|-1|24|-2049' '1|2|12|3'; do
    IFS='|' read -r left right out_width expected <<< "$example"
    printf '%s\n' "$left" > "$TMP/лівий.lisp"
    printf '%s\n' "$right" > "$TMP/правий.lisp"
    "$ROOT/build/m0.2/bin/senschyslo" --з-укр D12 \
      "$TMP/лівий.lisp" "$TMP/лівий.sens"
    "$ROOT/build/m0.2/bin/senschyslo" --з-укр D12 \
      "$TMP/правий.lisp" "$TMP/правий.sens"
    "$ROOT/build/m0.2/bin/senschyslododaty" D12 \
      "$TMP/лівий.sens" "$TMP/правий.sens" \
      > "$TMP/сума.sens" 2>"$TMP/сума.err"
    clean_heap_report "$TMP/сума.err"
    "$ROOT/build/m0.2/bin/senschyslo" --в-укр "D$out_width" \
      "$TMP/сума.sens" > "$TMP/фпц.txt"
    printf '(додати %s %s)\n' "$left" "$right" > "$TMP/вираз.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/вираз.lisp" \
      > "$TMP/сенс.txt" 2> "$TMP/сенс.err"
    printf '%s\n' "$expected" > "$TMP/очікуване.txt"
    cmp "$TMP/очікуване.txt" "$TMP/фпц.txt" || {
      echo "ДОДАВАННЯ-ПРОВАЛ: нативна сума $example" >&2; exit 1;
    }
    cmp "$TMP/фпц.txt" "$TMP/сенс.txt" || {
      echo "ДОДАВАННЯ-ОРАКУЛ-ПРОВАЛ: немає паритету $example" >&2
      cat "$TMP/сенс.err" >&2
      exit 1
    }
    rm -f "$TMP/лівий.sens" "$TMP/правий.sens"
  done
  echo 'ДОДАВАННЯ-ОРАКУЛ-ГАРАЗД pinned-SENS=точний FPC=4 D12=знак-розширення'
fi
