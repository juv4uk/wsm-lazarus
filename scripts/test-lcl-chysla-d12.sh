#!/usr/bin/env bash
# G3.29: справжній LCL/GTK2 тест числових даних D12–D192.
# Фізичні .sens утворює чинний FPC senschyslo, не GUI і не .lisp reader.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || {
  echo 'LCL-ЧИСЛА-D12-БЛОК: відсутній lazbuild' >&2; exit 127;
}
command -v xvfb-run >/dev/null || {
  echo 'LCL-ЧИСЛА-D12-БЛОК: відсутній xvfb-run' >&2; exit 127;
}
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# 4096/4096 D12 і D24–D192 + негативні канонічні/файлові свідки.
bash ./scripts/test-numericplane.sh
mkdir -p build/lcl-chysla-d12/bin build/lcl-chysla-d12/units
lazbuild --widgetset=gtk2 --build-all gui/sens-chysla-d12.lpi
BIN="$ROOT/build/lcl-chysla-d12/bin/sens-chysla-d12"
CLI="$ROOT/build/m0.2/bin/senschyslo"
test -x "$BIN" || { echo 'LCL-ЧИСЛА-D12-БЛОК: немає GUI binary' >&2; exit 1; }
test -x "$CLI" || { echo 'LCL-ЧИСЛА-D12-БЛОК: немає FPC numeric CLI' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '-2048' > "$TMP/дванадцять.lisp"
printf '%s\n' '-3138550867693340381917894711603833208051177722232017256448' > "$TMP/сто-девяносто-два.lisp"
"$CLI" --з-укр D12 "$TMP/дванадцять.lisp" "$TMP/дванадцять.sens"
"$CLI" --з-укр D192 "$TMP/сто-девяносто-два.lisp" "$TMP/сто-девяносто-два.sens"
test "$(stat -c '%a' "$TMP/дванадцять.sens")" = '600'
test "$(stat -c '%a' "$TMP/сто-девяносто-два.sens")" = '600'
printf '\363' > "$TMP/зіпсовано.sens"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x900x24' "$BIN" \
  --самоперевірка "$TMP/дванадцять.sens" \
  "$TMP/сто-девяносто-два.sens" "$TMP/зіпсовано.sens" \
  "$TMP/дванадцять.lisp" > "$TMP/stdout" 2> "$TMP/stderr"
test ! -s "$TMP/stderr" || {
  cat "$TMP/stderr" >&2
  echo 'LCL-ЧИСЛА-D12-ПОМИЛКА: непорожній stderr' >&2
  exit 1
}
grep -Fq 'LCL-ЧИСЛА-D12-ГАРАЗД' "$TMP/stdout"
grep -Fq 'арифметика=НЕ-ДОВЕДЕНА' "$TMP/stdout"
echo 'LAZARUS-ЧИСЛА-D12-ЗБІРКА-ГАРАЗД FPC=справжній LCL=GTK2/Xvfb D12-D192=точні'
