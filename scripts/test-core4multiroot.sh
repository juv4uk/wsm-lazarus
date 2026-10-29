#!/usr/bin/env bash
# G4.34 — справжній FPC/фізичне виконання змішаних Core4-коренів.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE4-КОРЕНІ-БЛОКЕР: немає FPC' >&2; exit 127; }
./scripts/check-pin.sh

UNITS="$ROOT/build/m0.2/core4-multiroot-units"
BIN="$ROOT/build/m0.2/core4-multiroot-bin"
mkdir -p "$UNITS" "$BIN"
for SRC in scripts/test-core4multiroot.pas src/senscore4koreni.lpr; do
  case "$SRC" in
    scripts/test-core4multiroot.pas) NAME=test-core4multiroot ;;
    *) NAME=senscore4koreni ;;
  esac
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -o"$NAME" "$ROOT/$SRC"
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$BIN/test-core4multiroot" "$ROOT" "$TMP" >"$TMP/test-out" 2>"$TMP/test-err"
grep -Fq 'CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД' "$TMP/test-out"
grep -Fq '0 unfreed memory blocks' "$TMP/test-err"

"$BIN/senscore4koreni" --виконати-корені "$ROOT" \
  "$TMP/good.sens" "$TMP/result.sens" >"$TMP/stdout" 2>"$TMP/stderr"
cmp "$TMP/expected.sens" "$TMP/result.sens"
grep -Fq 'CORE4-КОРЕНІ-ГАРАЗД' "$TMP/stdout"
grep -Fq '0 unfreed memory blocks' "$TMP/stderr"

expect_bad() {
  local target="$1" fragment="$2"
  shift 2
  local rc=0
  "$BIN/senscore4koreni" --виконати-корені "$ROOT" "$@" "$target" \
    >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "CORE4-КОРЕНІ-ПОМИЛКА: код $rc замість 2" >&2
    exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/stdout"
  grep -Fq "$fragment" "$TMP/stderr"
  grep -Fq '0 unfreed memory blocks' "$TMP/stderr"
}
expect_bad "$TMP/late-output.sens" 'форма=3' "$TMP/late.sens"
expect_bad "$TMP/too-many-output.sens" '1..64' "$TMP/too-many.sens"
expect_bad "$TMP/broken-output.sens" 'T5M' "$TMP/broken.sens"

# Реальний захист від перезапису звичайної цілі.
cp "$TMP/expected.sens" "$TMP/original.sens"
rc=0
"$BIN/senscore4koreni" --виконати-корені "$ROOT" \
  "$TMP/good.sens" "$TMP/result.sens" >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
test "$rc" -eq 2
cmp "$TMP/expected.sens" "$TMP/result.sens"
test ! -s "$TMP/stdout"
# Dangling symlink теж є зайнятою ціллю, хоча FileExists=False.
ln -s "$TMP/неіснуючий.sens" "$TMP/посилання.sens"
rc=0
"$BIN/senscore4koreni" --виконати-корені "$ROOT" \
  "$TMP/good.sens" "$TMP/посилання.sens" >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
test "$rc" -eq 2
test -L "$TMP/посилання.sens"
test "$(readlink "$TMP/посилання.sens")" = "$TMP/неіснуючий.sens"
test ! -e "$TMP/неіснуючий.sens"
test ! -s "$TMP/stdout"
# У всіх гілках тимчасовий фізичний файл прибраний.
if find "$TMP" -maxdepth 1 -name 'c4k*' -print -quit | grep -q .; then
  echo 'CORE4-КОРЕНІ-ПОМИЛКА: залишилися тимчасові файли' >&2
  exit 1
fi
echo 'CORE4-КОРЕНІ-ГАРАЗД FPC=справжній ядро=1/3/64 no-clobber=так негативні=7'
