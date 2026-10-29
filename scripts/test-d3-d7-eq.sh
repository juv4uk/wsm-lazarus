#!/usr/bin/env bash
# G3.29: фізичне D3:101 з D7, лише незалежний pinned SENS є oracle.
# Вхідний файл .sens для обох виконавців ідентичний byte-for-byte.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in git timeout cmp awk; do
  command -v "$tool" >/dev/null || {
    echo "ТОЧНИЙ-Д7-БЛОК: бракує $tool" >&2; exit 127;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ТОЧНИЙ-Д7-БЛОК: відсутній FPC' >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(eq-operands . admitted-atoms-only)'
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(eq-result . (D1:0 D1:1))'
grep -Fq '0010110' external/sens/lib/domains/d7.lisp

ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'ТОЧНИЙ-Д7-БЛОК: незалежний pinned SENS REPL не зібрано' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'ТОЧНИЙ-Д7-БЛОК: зовнішній REPL не відповідає pin' >&2; exit 1;
}

mkdir -p build/m0.2/d3-d7-eq-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/d3-d7-eq-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-d3-d7-eq \
  "$ROOT/scripts/test-d3-d7-eq.pas"
# G3.37: чистий stdout із того самого native executor, без host framing.
# Реальний checked FPC build; зібрані тут вихідні байти порівнюються
# із вже збереженим `ExecutePhysicalT5M` та незалежним pinned REPL.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/d3-d7-eq-units" \
  -FE"$ROOT/build/m0.2/bin" -osensvykon \
  "$ROOT/src/sensvykon.lpr"
timeout 90s ./build/m0.2/bin/test-d3-d7-eq

# Усі раніші D1 EQ, D3 COND, фізичні цитати, негативні D2/Т5M
# лишаються увімкненими: жодного послаблення заради нового профілю.
timeout 240s bash ./scripts/test-native-eq.sh

COUNT=0
# G3.33: додатково фізичний D3:010 над D1, D7 і структурною
# D2 парою. Усі кейси — ті самі canonical packed .sens для двох runtime.
for case_name in syn-tak syn-ni d7-high-tak d7-high-ni \
  d1-d7-ni d7-d1-ni d1-tak d1-ni \
  atom-d1-tak atom-d1-zero atom-d7-syn atom-d7-high \
  atom-cons-d1 atom-cons-d7; do
  INPUT="$ROOT/build/m0.2/d3-d7-eq-$case_name.sens"
  EXPECT="$ROOT/build/m0.2/d3-d7-eq-$case_name.expected"
  PHYSICAL="$ROOT/build/m0.2/d3-d7-eq-$case_name.answer.sens"
  test -s "$INPUT" && test -s "$PHYSICAL" && test -s "$EXPECT"
  # Справжній виконуваний `sensvykon` приймає той самий .sens.
  # Відмова повинна залишити ПУСТИЙ stdout, а успішний результат —
  # рівно канонічні packed T5M без жодного текстового перенесення рядка.
  timeout 30s "$ROOT/build/m0.2/bin/sensvykon" --виконати-сенс "$INPUT" \
    >"$ROOT/build/m0.2/d3-d7-eq-$case_name.cli.sens" \
    2>"$ROOT/build/m0.2/d3-d7-eq-$case_name.cli.err" || {
    echo "ДВІЙКОВИЙ-ОРАКУЛ-БЛОК: нативний CLI відхилив $case_name" >&2
    cat "$ROOT/build/m0.2/d3-d7-eq-$case_name.cli.err" >&2; exit 1
  }
  test ! -s "$ROOT/build/m0.2/d3-d7-eq-$case_name.cli.err"
  if ! cmp -s "$PHYSICAL" "$ROOT/build/m0.2/d3-d7-eq-$case_name.cli.sens"; then
    echo "ДВІЙКОВИЙ-ОРАКУЛ-РОЗБІЖНІСТЬ: $case_name" >&2
    exit 1
  fi
  test "$(wc -l < "$EXPECT")" -eq 1
  # Після компіляції pinned Rust/Zig SENS запускає ТОЙ САМИЙ input.
  # Це не .lisp mint, не host enum і не локальний еталон Pascal.
  timeout 60s "$ORACLE" "$INPUT" \
    >"$ROOT/build/m0.2/d3-d7-eq-$case_name.oracle" \
    2>"$ROOT/build/m0.2/d3-d7-eq-$case_name.oracle.err" || {
      echo "ТОЧНИЙ-Д7-ОРАКУЛ-ПРОВАЛ: upstream відхилив $case_name" >&2
      cat "$ROOT/build/m0.2/d3-d7-eq-$case_name.oracle.err" >&2; exit 1;
    }
  test ! -s "$ROOT/build/m0.2/d3-d7-eq-$case_name.oracle.err"
  if ! cmp -s "$EXPECT" "$ROOT/build/m0.2/d3-d7-eq-$case_name.oracle"; then
    echo "ТОЧНИЙ-Д7-ОРАКУЛ-РОЗБІЖНІСТЬ: $case_name" >&2
    diff -u "$EXPECT" "$ROOT/build/m0.2/d3-d7-eq-$case_name.oracle" >&2 || true
    exit 1
  fi
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 14
echo "D3-Д7-НЕЗАЛЕЖНИЙ-ОРАКУЛ-ГАРАЗД pinned=$PIN ті-самі-T5M=так фізичних-свідків=$COUNT FPC=реальний D7=дані D12+=відмова D3-АТОМ=виконано чистий-T5M-CLI=14"
