#!/usr/bin/env bash
# G6.54: real ELF Linux x86-64 + pinned SENS oracle на тих самих .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-Д7-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
for tool in "$FPC_BIN" timeout readelf objdump cmp; do
  command -v "$tool" >/dev/null || {
    echo "ЕЛФ-Д7-БЛОК: відсутній $tool" >&2;exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" && test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'ЕЛФ-Д7-БЛОК: відсутній незалежний pinned SENS' >&2;exit 127;
}
# Обов'язкова незмінена D1 native regression + незалежний D7 FPC runtime oracle.
timeout 240s bash ./scripts/test-elfeqt5m.sh
timeout 240s bash ./scripts/test-d3-d7-eq.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p build/m0.2/elfd7eq/units build/m0.2/elfd7eq/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/elfd7eq/units" \
  -FE"$ROOT/build/m0.2/elfd7eq/bin" \
  -otest-elfd7eq "$ROOT/scripts/test-elfd7eq.pas"
timeout 30s "$ROOT/build/m0.2/elfd7eq/bin/test-elfd7eq" \
  "$ROOT/external/sens" "$TMP"
COUNT=0
for label in син-однакові син-різні старший-однакові старший-різні \
             нулі-однакові нулі-різні; do
  ELF="$TMP/$label.elf"
  INPUT="$TMP/$label.sens"
  test -s "$ELF" && test -s "$INPUT"
  chmod u+x "$ELF"
  readelf -h "$ELF" > "$TMP/заголовок"
  readelf -l "$ELF" > "$TMP/ділянки"
  grep -F 'ELF64' "$TMP/заголовок" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/заголовок" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/заголовок" >/dev/null
  grep -F 'LOAD' "$TMP/ділянки" >/dev/null
  tail -c +121 "$ELF" > "$TMP/код"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/код" > "$TMP/асемблер"
  test "$(grep -c 'xor.*cl' "$TMP/асемблер")" -eq 7
  grep -F 'sete' "$TMP/асемблер" >/dev/null
  timeout 5s "$ELF" > "$TMP/машина.sens"
  cmp "$TMP/машина.sens" "$TMP/$label.expected.sens"
  test "$(wc -c < "$TMP/машина.sens")" -eq 1
  # Незалежний upstream SENS обчислює ТОЙ САМИЙ фізичний T5M файл.
  timeout 60s "$ORACLE" "$INPUT" \
    > "$TMP/$label.oracle" 2> "$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  cmp "$TMP/$label.oracle" "$TMP/$label.expected.txt"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 6
echo "ЕЛФ-Д7-МАШИНА-ГАРАЗД FPC=реальний Linux=x86-64 ELF64=6 XOR/SETE=виконано негативи=12 D1-регресія=4 незалежний-pinned-SENS=$COUNT T5M=побайтово"
