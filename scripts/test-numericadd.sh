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
"$ROOT/build/m0.2/bin/test-numericadd" "$TMP"
"$ROOT/build/m0.2/bin/senschyslododaty" D12 \
  "$TMP/left.sens" "$TMP/right.sens" >"$TMP/result.sens" 2>"$TMP/ok.err"
grep -Fq "0 unfreed memory blocks" "$TMP/ok.err" || {
  echo "ДОДАВАННЯ-ПРОВАЛ: HeapTrc не підтвердив нуль витоків" >&2
  cat "$TMP/ok.err" >&2
  exit 1
}
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
