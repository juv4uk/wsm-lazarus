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
if ! "$BIN/test-core4multiroot" "$ROOT" "$TMP" >"$TMP/test-out" 2>"$TMP/test-err"; then
  cat "$TMP/test-out" >&2
  cat "$TMP/test-err" >&2
  echo "CORE4-КОРЕНІ-ПОМИЛКА: власний фізичний свідок не пройшов" >&2
  exit 1
fi
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
# G4.36: одна ІЗ УЖЕ ВИКОНАНИХ фізичних відповідей (не новий evaluator).
# Список повинен зберегти свою D2-рамку 10/01, W24 — 24 провідні біти.
pick_ok() {
  local index="$1" source="$2" expected="$3" target="$4"
  "$BIN/senscore4koreni" --виконати-й-вибрати "$ROOT" "$index" \
    "$source" "$target" >"$TMP/stdout" 2>"$TMP/stderr"
  cmp "$expected" "$target"
  grep -Fq "CORE4-ВИБІР-ГАРАЗД корінь=$index" "$TMP/stdout"
  grep -Fq '0 unfreed memory blocks' "$TMP/stderr"
}
pick_ok 1 "$TMP/good.sens" "$TMP/single-1.sens" "$TMP/picked-1.sens"
pick_ok 2 "$TMP/good.sens" "$TMP/single-2.sens" "$TMP/picked-2.sens"
pick_ok 3 "$TMP/good.sens" "$TMP/single-3.sens" "$TMP/picked-3.sens"
pick_ok 1 "$TMP/large.sens" "$TMP/single-64-first.sens" "$TMP/picked-64-first.sens"
pick_ok 64 "$TMP/large.sens" "$TMP/single-2.sens" "$TMP/picked-64-last.sens"

expect_pick_bad() {
  local target="$1" fragment="$2" index="$3" source="$4" rc=0
  "$BIN/senscore4koreni" --виконати-й-вибрати "$ROOT" "$index" \
    "$source" "$target" >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "CORE4-ВИБІР-ПОМИЛКА: код $rc замість 2 індекс=$index" >&2
    exit 1
  fi
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/stdout"
  grep -Fq "$fragment" "$TMP/stderr"
  grep -Fq '0 unfreed memory blocks' "$TMP/stderr"
}
expect_pick_bad "$TMP/bad-zero.sens" 'індекс відповіді' 0 "$TMP/good.sens"
expect_pick_bad "$TMP/bad-four.sens" 'відсутній серед D2-коренів' 4 "$TMP/good.sens"
expect_pick_bad "$TMP/bad-65.sens" 'індекс відповіді' 65 "$TMP/large.sens"
expect_pick_bad "$TMP/bad-leading.sens" 'індекс відповіді' 01 "$TMP/good.sens"
expect_pick_bad "$TMP/bad-text.sens" 'індекс відповіді' а "$TMP/good.sens"
expect_pick_bad "$TMP/bad-late.sens" 'форма=3' 1 "$TMP/late.sens"
expect_pick_bad "$TMP/bad-broken.sens" 'T5M' 2 "$TMP/broken.sens"
expect_pick_bad "$TMP/bad-overflow.sens" '1..64' 1 "$TMP/too-many.sens"

# Уже виданий selected результат не можна перезаписати (навіть байт-у-байт).
rc=0
"$BIN/senscore4koreni" --виконати-й-вибрати "$ROOT" 1 \
  "$TMP/good.sens" "$TMP/picked-1.sens" >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/stdout"
grep -Fq 'ціль уже існує' "$TMP/stderr"
cmp "$TMP/picked-1.sens" "$TMP/single-1.sens"

# Із висячим symlink та самим source=output також жодного clobber.
ln -s "$TMP/відсутній.sens" "$TMP/посилання-вибору.sens"
rc=0
"$BIN/senscore4koreni" --виконати-й-вибрати "$ROOT" 2 \
  "$TMP/good.sens" "$TMP/посилання-вибору.sens" \
  >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/stdout"
test -L "$TMP/посилання-вибору.sens"
test "$(readlink "$TMP/посилання-вибору.sens")" = "$TMP/відсутній.sens"
test ! -e "$TMP/відсутній.sens"
cp "$TMP/good.sens" "$TMP/good.backup.sens"
rc=0
"$BIN/senscore4koreni" --виконати-й-вибрати "$ROOT" 1 \
  "$TMP/good.sens" "$TMP/good.sens" >"$TMP/stdout" 2>"$TMP/stderr" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/stdout"
cmp "$TMP/good.backup.sens" "$TMP/good.sens"

# Після серії відмов фізичний Core4 все ще виконує нову програму.
pick_ok 2 "$TMP/good.sens" "$TMP/single-2.sens" "$TMP/recovered.sens"

# У всіх гілках тимчасовий фізичний файл прибраний.
if find "$TMP" -maxdepth 1 -name 'c4k*' -print -quit | grep -q .; then
  echo 'CORE4-КОРЕНІ-ПОМИЛКА: залишилися тимчасові файли' >&2
  exit 1
fi
echo 'CORE4-КОРЕНІ-ГАРАЗД FPC=справжній ядро=1/3/64 no-clobber=так негативні=7 вибір=1/2/3/64 позитиви=5 вибір-негативи=11'
