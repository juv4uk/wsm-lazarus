#!/usr/bin/env bash
# Доказ в чинному Free Pascal, без другого reader, механізму D3 чи LCL.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ПОМИЛКА: Free Pascal не знайдено' >&2
  exit 127
}
mkdir -p build/m0.2/execfault-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/execfault-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-execfault "$ROOT/scripts/test-execfault.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/execfault-units" -FE"$ROOT/build/m0.2/bin" \
  -osenspomylka "$ROOT/src/senspomylka.lpr"
./build/m0.2/bin/test-execfault
result=$(./build/m0.2/bin/senspomylka --виконати build/m0.2/execfault-valid.sens)
[[ "$result" == '(1)' ]] || { echo 'Помилка: фактичний D3 результат змінено' >&2; exit 1; }
check_failure() {
  local path="$1" pattern="$2" description="$3"
  if ./build/m0.2/bin/senspomylka --виконати "$path" \
    >build/m0.2/execfault-error.out 2>build/m0.2/execfault-error.err; then
    echo "ПОМИЛКА: прийнято $description" >&2; exit 1
  fi
  [[ ! -s build/m0.2/execfault-error.out ]] || {
    echo "ПОМИЛКА: частковий stdout для $description" >&2; exit 1;
  }
  grep -Fq "$pattern" build/m0.2/execfault-error.err || {
    echo "ПОМИЛКА: втрачено фізичну адресу $description" >&2
    cat build/m0.2/execfault-error.err >&2
    exit 1
  }
}
check_failure build/m0.2/execfault-quote.sens \
  'слово=2 трити=[3,6) байти=[0,2)' 'блокована D3 цитата'
check_failure build/m0.2/execfault-nested.sens \
  'слово=6 трити=[16,17) байти=[3,4)' 'невалідна вкладена гілка D3'
check_failure build/m0.2/execfault-eof.sens \
  'слово=3 трити=[4,4) байти=[1,1) EOF' 'D2 кінець файлу'
check_failure build/m0.2/execfault-corrupt.sens \
  'слово=0 інтервал=невідомий' 'пошкоджений T5M'
echo 'EXECFAULT-CLI-OK двійковий=.sens фізичне=слово+трити+байти неповний_stdout=ні'
