#!/usr/bin/env bash
# G3.17. Чинний FPC виконує фізичні D3; запис результату atomic/no-clobber.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ПАКЕТ-D3-CLI: потрібен FPC' >&2; exit 127; }
DIR="$ROOT/build/paketd3-cli"
mkdir -p "$DIR/units" "$DIR/bin" "$DIR/fixtures" "$DIR/result"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$DIR/units" -FE"$DIR/bin" -osenspaketd3 "$ROOT/src/senspaketd3.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$DIR/units" -FE"$DIR/bin" -otest-paketd3-fixtures \
  "$ROOT/scripts/test-paketd3-cli-fixtures.pas"
"$DIR/bin/test-paketd3-fixtures" "$DIR/fixtures" >"$DIR/fixtures.log" 2>&1
BIN="$DIR/bin/senspaketd3"
ok() {
  local name="$1" count="$2"
  "$BIN" --пакет external/sens "$DIR/fixtures/$name.sens" \
    "$DIR/result/$name.sens" >"$DIR/$name.log" 2>&1
  cmp "$DIR/fixtures/$name-answer.sens" "$DIR/result/$name.sens"
  grep -Fq "ПАКЕТ-D3-ГОТОВО форм=$count" "$DIR/$name.log"
  grep -Fq '0 unfreed memory blocks' "$DIR/$name.log"
}
bad() {
  local label="$1"; shift
  if "$BIN" "$@" >"$DIR/reject.out" 2>"$DIR/reject.err"; then
    echo "ПОМИЛКА-ПАКЕТ-D3: прийнято $label" >&2; exit 1
  fi
  if [[ -s "$DIR/reject.out" ]]; then
    echo "ПОМИЛКА-ПАКЕТ-D3: частковий stdout ($label)" >&2; exit 1
  fi
  grep -Fq 'ПОМИЛКА-ПАКЕТ-D3' "$DIR/reject.err" || {
    echo "ПОМИЛКА-ПАКЕТ-D3: відсутня діагностика ($label)" >&2; exit 1;
  }
}
ok one 1
ok four 4
ok 64 64
bad '65 форм' --пакет external/sens "$DIR/fixtures/65.sens" "$DIR/result/65.sens"
[[ ! -e "$DIR/result/65.sens" ]]
bad 'пізня D3-помилка' --пакет external/sens "$DIR/fixtures/late-bad.sens" "$DIR/result/late.sens"
grep -Fq 'форма=2 слово=2' "$DIR/reject.err"
[[ ! -e "$DIR/result/late.sens" ]]
bad 'неканонічний T5M' --пакет external/sens "$DIR/fixtures/bad-t5m.sens" "$DIR/result/bad.sens"
[[ ! -e "$DIR/result/bad.sens" ]]
bad 'D12+ поза runtime' --пакет external/sens "$DIR/fixtures/d12.sens" "$DIR/result/d12.sens"
[[ ! -e "$DIR/result/d12.sens" ]]
bad 'людська проєкція не машина' --пакет external/sens "$DIR/fixtures/not-program.lisp" "$DIR/result/not-program.sens"
[[ ! -e "$DIR/result/not-program.sens" ]]
bad 'неіснуючий ввід' --пакет external/sens "$DIR/fixtures/missing.sens" "$DIR/result/missing.sens"
[[ ! -e "$DIR/result/missing.sens" ]]
bad 'відсутня директорія' --пакет external/sens "$DIR/fixtures/one.sens" "$DIR/result/no-such-dir/out.sens"
[[ ! -e "$DIR/result/no-such-dir/out.sens" ]]
cp "$DIR/fixtures/four-answer.sens" "$DIR/result/occupied.sens"
bad 'зайнятий результат' --пакет external/sens "$DIR/fixtures/one.sens" "$DIR/result/occupied.sens"
cmp "$DIR/fixtures/four-answer.sens" "$DIR/result/occupied.sens"
ln -s "$DIR/fixtures/four-answer.sens" "$DIR/result/alias.sens"
bad 'символічний лінк' --пакет external/sens "$DIR/fixtures/one.sens" "$DIR/result/alias.sens"
[[ -L "$DIR/result/alias.sens" ]]
bad 'хибний режим' --помилка external/sens "$DIR/fixtures/one.sens" "$DIR/result/mode.sens"
bad 'хибний вихід .lisp' --пакет external/sens "$DIR/fixtures/one.sens" "$DIR/result/forbidden.lisp"
[[ ! -e "$DIR/result/forbidden.lisp" ]]
echo 'ПАКЕТ-D3-CLI-ГАРАЗД: FPC/T5M 1,4,64; негативи=11; no-clobber=так; D12+=відхилено; Core4/REPL=НЕ-ДОВЕДЕНО'
