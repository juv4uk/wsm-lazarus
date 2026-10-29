#!/usr/bin/env bash
# G2.51: реальний FPC, один фізичний D7 / D12+ атом без текстового dispatch.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'СВІДОК-АТОМА-БЛОКЕР: немає FPC' >&2; exit 127; }
mkdir -p build/m0.2/svidok-atoma/units build/m0.2/svidok-atoma/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/svidok-atoma/units" \
  -FE"$ROOT/build/m0.2/svidok-atoma/bin" -osenssvidokatoma \
  src/senssvidokatoma.lpr
BIN="$ROOT/build/m0.2/svidok-atoma/bin/senssvidokatoma"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Реальні T5M свідки генерує ВЖЕ наявний фізичний FPC codec, не Python.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/svidok-atoma/units" \
  -FE"$ROOT/build/m0.2/svidok-atoma/bin" -osenst5m src/senst5m.lpr
PACK="$ROOT/build/m0.2/svidok-atoma/bin/senst5m"
make_atom() {
  local bits="$1" path="$2"
  printf '%s\n' "$bits" > "$TMP/слова.txt"
  timeout 20s "$PACK" --пакувати-слова "$TMP/слова.txt" > "$path"
}
reject() {
  local label="$1"; shift
  local status=0
  timeout 20s "$BIN" "$@" > "$TMP/відмова.out" 2> "$TMP/відмова.err" || status=$?
  test "$status" -eq 2 || { echo "НЕВІРНИЙ-КОД $label: $status" >&2; exit 1; }
  test ! -s "$TMP/відмова.out" || { echo "ЧАСТКОВИЙ-STDOUT $label" >&2; exit 1; }
  grep -Fq 'СВІДОК-АТОМА-ПОМИЛКА:' "$TMP/відмова.err"
}
make_atom 0101001 "$TMP/дужка.sens"
timeout 20s "$BIN" external/sens --атом D7 "$TMP/дужка.sens" > "$TMP/д7.out"
grep -Fxq 'домен: D7' "$TMP/д7.out"
grep -Fxq 'біти: 0101001' "$TMP/д7.out"
grep -Fxq 'трити: [0,7)' "$TMP/д7.out"
grep -Fxq 'байти: [0,2)' "$TMP/д7.out"
for surface in ук укр san en LISP sym; do
  grep -q "^$surface: " "$TMP/д7.out"
done
grep -Fq 'викличність: не-перевірено' "$TMP/д7.out"
make_atom 0010110 "$TMP/синхронізація.sens"
timeout 20s "$BIN" external/sens --атом D7 "$TMP/синхронізація.sens" > "$TMP/syn.out"
grep -Fxq 'біти: 0010110' "$TMP/syn.out"
grep -Fxq 'укр: (відсутня)' "$TMP/syn.out"
grep -Fxq 'LISP: (відсутня)' "$TMP/syn.out"
for width in 12 24 48 96 192; do
  printf -v zeros '%*s' "$width" ''
  zeros=${zeros// /0}
  ones=${zeros//0/1}
  make_atom "$ones" "$TMP/мінус-один.sens"
  timeout 20s "$BIN" external/sens --атом "D$width" "$TMP/мінус-один.sens" > "$TMP/число.out"
  grep -Fxq "домен: D$width" "$TMP/число.out"
  grep -Fxq "біти: $ones" "$TMP/число.out"
  grep -Fxq 'укр-число: -1' "$TMP/число.out"
  grep -Fxq 'арифметика: не-виконувалася' "$TMP/число.out"
  grep -Fxq "трити: [0,$width)" "$TMP/число.out"
  grep -Fxq "байти: [0,$(((width+4)/5)))" "$TMP/число.out"
  reject 'вузький домен' external/sens --атом D7 "$TMP/мінус-один.sens"
done
make_atom 000000000000 "$TMP/нуль.sens"
timeout 20s "$BIN" external/sens --атом D12 "$TMP/нуль.sens" > "$TMP/нуль.out"
grep -Fxq 'біти: 000000000000' "$TMP/нуль.out"
grep -Fxq 'укр-число: 0' "$TMP/нуль.out"
reject 'D12 як D7' external/sens --атом D7 "$TMP/нуль.sens"
reject 'D7 як D12' external/sens --атом D12 "$TMP/дужка.sens"
reject 'невідомий домен' external/sens --атом D11 "$TMP/нуль.sens"
reject 'домен без канону' external/sens --атом D012 "$TMP/нуль.sens"
reject 'без pinned SENS' "$TMP/відсутня" --атом D12 "$TMP/нуль.sens"
reject 'немає файла' external/sens --атом D12 "$TMP/відсутній.sens"
cp "$TMP/нуль.sens" "$TMP/пізня.sens"
printf '\363' >> "$TMP/пізня.sens"
reject 'зіпсований T5M' external/sens --атом D12 "$TMP/пізня.sens"
printf '000000000000 000000000000\n' > "$TMP/слова.txt"
timeout 20s "$PACK" --пакувати-слова "$TMP/слова.txt" > "$TMP/два.sens"
reject 'два слова' external/sens --атом D12 "$TMP/два.sens"
printf '000000000000\n' > "$TMP/текст.lisp"
reject 'проєкція замість фізичного' external/sens --атом D12 "$TMP/текст.lisp"
reject 'невірна дія' external/sens --читати D12 "$TMP/нуль.sens"
timeout 20s "$BIN" external/sens --атом D12 "$TMP/нуль.sens" > "$TMP/після.out"
cmp "$TMP/нуль.out" "$TMP/після.out"
echo 'СВІДОК-АТОМА-ГАРАЗД FPC=реальний D7=6-проєкцій D12-D192=явні фізичний-T5M=так'
