#!/usr/bin/env bash
# G4.37: два справжні Core4 виконавці претендують на ОДНЕ фізичне ім'я.
# Це тест механізму атомарної публікації, а не нове правило SENS.
set -euo pipefail
export LC_ALL=C.UTF-8
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE4-ГОНКИ-БЛОКЕР: немає справжнього FPC' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'CORE4-ГОНКИ-БЛОКЕР: немає timeout' >&2; exit 127; }
command -v stat >/dev/null || { echo 'CORE4-ГОНКИ-БЛОКЕР: немає stat' >&2; exit 127; }
./scripts/check-pin.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Раніше злиті набори залишаємо ПОВНИМИ, не послаблюємо негативів.
for suite in scripts/test-core4multiroot.sh scripts/test-core4runtime.sh; do
  if ! timeout --signal=TERM --kill-after=5s 240s bash "$suite" >"$TMP/regression.log" 2>&1; then
    cat "$TMP/regression.log" >&2
    echo "CORE4-ГОНКИ-ПОМИЛКА: чинна регресія $suite" >&2
    exit 1
  fi
done

UNITS="$ROOT/build/m0.2/core4-concurrency-units"
BIN="$ROOT/build/m0.2/core4-concurrency-bin"
mkdir -p "$UNITS" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-core4vykon-fixtures "$ROOT/scripts/test-core4vykon-fixtures.pas"
if ! "$BIN/test-core4vykon-fixtures" "$ROOT" "$TMP" >"$TMP/fixture-out" 2>"$TMP/fixture-err"; then
  cat "$TMP/fixture-err" >&2; exit 1
fi
grep -Fq 'CORE4-СВІДКИ-ГОТОВО' "$TMP/fixture-out"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture-err"

# Фізичні «атом + D2 список + opaque W24» отримуємо з НАЯВНОГО
# G4.34 pinned runtime-свідка. У новому тесті немає копії Core4-законів.
MIX_BIN="$ROOT/build/m0.2/core4-multiroot-bin"
if ! "$MIX_BIN/test-core4multiroot" "$ROOT" "$TMP" >"$TMP/mixed-out" 2>"$TMP/mixed-err"; then
  cat "$TMP/mixed-err" >&2; exit 1
fi
grep -Fq 'CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД' "$TMP/mixed-out"
grep -Fq '0 unfreed memory blocks' "$TMP/mixed-err"
CLI="$MIX_BIN/senscore4koreni"
test -x "$CLI"
cmp -s "$TMP/good.sens" "$TMP/ni.sens" && {
  echo 'CORE4-ГОНКИ-ПОМИЛКА: різні свідки фізично однакові' >&2; exit 1;
}
cmp -s "$TMP/expected.sens" "$TMP/ni-chek.sens" && {
  echo 'CORE4-ГОНКИ-ПОМИЛКА: результати гонки не розрізняються' >&2; exit 1;
}

# Не покладатися на прихований захист umask: навіть із відкритою\n# host-маскою 000 відповідь має бути приватною від моменту mkstemp.\numask 000\n\n# Перш ніж випробувати одночасне створення, кожна програма має
# НАСПРАВДІ виконатись окремо через той самий FPC CLI.
for flavor in mixed single; do
  if [[ "$flavor" == mixed ]]; then
    input="$TMP/good.sens"; reference="$TMP/expected.sens"
  else
    input="$TMP/ni.sens"; reference="$TMP/ni-chek.sens"
  fi
  timeout --signal=TERM --kill-after=2s 30s "$CLI" --виконати-корені \
    "$ROOT" "$input" "$TMP/standalone-$flavor.sens" \
    >"$TMP/standalone-$flavor.out" 2>"$TMP/standalone-$flavor.err"
  cmp "$reference" "$TMP/standalone-$flavor.sens"
  grep -Fxq 'CORE4-КОРЕНІ-ГАРАЗД' "$TMP/standalone-$flavor.out"
  grep -Fq '0 unfreed memory blocks' "$TMP/standalone-$flavor.err"
done

# Функція перевіряє чітко переможця й відхиленого. Кожен процес має
# ВЛАСНИЙ PID, stdout, stderr; статус 124 означає невиправданий timeout.
check_actor() {
  local index="$1" actor="$2" rc="$3" expected="$4" dest="$5"
  local out="$TMP/$index-$actor.out" err="$TMP/$index-$actor.err"
  if [[ "$rc" == 0 ]]; then
    cmp "$expected" "$dest"
    grep -Fxq 'CORE4-КОРЕНІ-ГАРАЗД' "$out"
  elif [[ "$rc" == 2 ]]; then
    test ! -s "$out"
    grep -Fq 'CORE4-КОРЕНІ-ПОМИЛКА:' "$err"
  else
    echo "CORE4-ГОНКИ-ПОМИЛКА: $actor завершився кодом $rc" >&2
    cat "$err" >&2 || true
    exit 1
  fi
  grep -Fq '0 unfreed memory blocks' "$err"
}

# 24 одночасні двопроцесні звернення до одного нового імені.
# Відповіді РІЗНІ: 3 D2-корені зі списком або 1 точний D1:0.
# Зберігаємо всі порушення режиму доступу, але наприкінці ОБОВ'ЯЗКОВО
# провалюємо gate. Це дозволяє перевірити усі 32 гонки, не приховуючи баг.
privacy_failures=0
for index in $(seq 1 24); do
  dest="$TMP/переможець-$index.sens"
  timeout --signal=TERM --kill-after=2s 30s "$CLI" --виконати-корені \
    "$ROOT" "$TMP/good.sens" "$dest" \
    >"$TMP/$index-mixed.out" 2>"$TMP/$index-mixed.err" &
  first=$!
  timeout --signal=TERM --kill-after=2s 30s "$CLI" --виконати-корені \
    "$ROOT" "$TMP/ni.sens" "$dest" \
    >"$TMP/$index-single.out" 2>"$TMP/$index-single.err" &
  second=$!
  rc1=0; wait "$first" || rc1=$?
  rc2=0; wait "$second" || rc2=$?
  if [[ "$rc1" == 0 && "$rc2" == 2 ]]; then
    cmp "$TMP/expected.sens" "$dest"
  elif [[ "$rc1" == 2 && "$rc2" == 0 ]]; then
    cmp "$TMP/ni-chek.sens" "$dest"
  else
    echo "CORE4-ГОНКИ-ПОМИЛКА: не один переможець у $index ($rc1/$rc2)" >&2
    cat "$TMP/$index-mixed.err" "$TMP/$index-single.err" >&2 || true
    exit 1
  fi
  check_actor "$index" mixed "$rc1" "$TMP/expected.sens" "$dest"
  check_actor "$index" single "$rc2" "$TMP/ni-chek.sens" "$dest"
  actual_mode=$(stat -c '%a' "$dest")
  if [[ "$actual_mode" != 600 ]]; then
    (( privacy_failures += 1 ))
    echo "CORE4-ГОНКИ-ПРАВА: відповідь=$index фактично=$actual_mode очікувано=600" >&2
  fi
done

# У процесі пізньої помилки вже є дві обчислені форми, але третя
# повинна відхилити весь пакет. Інший процес має успішно опублікувати
# повний canonical .sens, незалежно від порядку завершення.
for index in $(seq 25 32); do
  dest="$TMP/відмова-$index.sens"
  timeout --signal=TERM --kill-after=2s 30s "$CLI" --виконати-корені \
    "$ROOT" "$TMP/late.sens" "$dest" \
    >"$TMP/$index-late.out" 2>"$TMP/$index-late.err" &
  first=$!
  timeout --signal=TERM --kill-after=2s 30s "$CLI" --виконати-корені \
    "$ROOT" "$TMP/good.sens" "$dest" \
    >"$TMP/$index-mixed.out" 2>"$TMP/$index-mixed.err" &
  second=$!
  rc1=0; wait "$first" || rc1=$?
  rc2=0; wait "$second" || rc2=$?
  [[ "$rc1" == 2 && "$rc2" == 0 ]] || {
    echo "CORE4-ГОНКИ-ПОМИЛКА: пізня відмова ($rc1/$rc2) у $index" >&2
    exit 1
  }
  check_actor "$index" late "$rc1" "$TMP/expected.sens" "$dest"
  grep -Fq 'форма=3' "$TMP/$index-late.err"
  check_actor "$index" mixed "$rc2" "$TMP/expected.sens" "$dest"
  cmp "$TMP/expected.sens" "$dest"
done

# Існуюче ім'я та висяче символьне посилання не можна замінити.
cp "$TMP/ni-chek.sens" "$TMP/зайнято.sens"
ln -s "$TMP/відсутній.sens" "$TMP/висяче.sens"
for target in "$TMP/зайнято.sens" "$TMP/висяче.sens"; do
  rc=0
  timeout --signal=TERM --kill-after=2s 30s "$CLI" --виконати-корені \
    "$ROOT" "$TMP/good.sens" "$target" \
    >"$TMP/protected.out" 2>"$TMP/protected.err" || rc=$?
  [[ "$rc" == 2 ]]
  test ! -s "$TMP/protected.out"
  grep -Fq 'CORE4-КОРЕНІ-ПОМИЛКА:' "$TMP/protected.err"
done
cmp "$TMP/ni-chek.sens" "$TMP/зайнято.sens"
test -L "$TMP/висяче.sens"
test "$(readlink "$TMP/висяче.sens")" = "$TMP/відсутній.sens"
test ! -e "$TMP/відсутній.sens"

# У разі будь-якої відмови в цільовому каталозі не залишається
# власного фізичного тимчасового файла.
if find "$TMP" -maxdepth 1 -name 'c4k*' -print -quit | grep -q .; then
  echo 'CORE4-ГОНКИ-ПОМИЛКА: є невидалений тимчасовий файл c4k' >&2
  exit 1
fi
if (( privacy_failures != 0 )); then
  echo "CORE4-ГОНКИ-БЛОКЕР: гонки=32/32 перевірено; приватні права 0600 порушено у $privacy_failures/24 файлів" >&2
  exit 1
fi
echo 'CORE4-КОНКУРЕНЦІЯ-ГАРАЗД процеси=64 пари=32 різні-відповіді=24 пізня-відмова=8 режим=0600 no-clobber=так T5M=байт-у-байт'
