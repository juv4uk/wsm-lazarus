#!/usr/bin/env bash
# G4.10: реальний FPC Core4 CLI, фізичні .sens та негативні сценарії.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'CORE4-CLI-БЛОКЕР: не встановлено Free Pascal' >&2
  exit 127
}
./scripts/check-pin.sh

UNITS="$ROOT/build/m0.2/core4-cli-units"
BIN="$ROOT/build/m0.2/bin"
mkdir -p "$UNITS" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -osenscore4vykon "$ROOT/src/senscore4vykon.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-core4vykon-fixtures "$ROOT/scripts/test-core4vykon-fixtures.pas"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$BIN/test-core4vykon-fixtures" "$ROOT" "$TMP"

for name in tak ni d24 global; do
  "$BIN/senscore4vykon" --виконати "$ROOT" \
    "$TMP/$name.sens" "$TMP/$name-result.sens" >"$TMP/stdout" 2>"$TMP/stderr"
  cmp "$TMP/$name-chek.sens" "$TMP/$name-result.sens"
  grep -q 'CORE4-ВИКОНАНО' "$TMP/stdout"
done

expect_failure() {
  local expected="$1" target="$2"
  shift 2
  local actual=0
  "$@" >"$TMP/stdout" 2>"$TMP/stderr" || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    echo "CORE4-CLI-ПОМИЛКА: очікувався код $expected, отримано $actual" >&2
    exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/stdout"
  test -s "$TMP/stderr"
}

expect_failure 2 "$TMP/bad-out.sens" \
  "$BIN/senscore4vykon" --виконати "$ROOT" "$TMP/poshkodzheno.sens" "$TMP/bad-out.sens"
expect_failure 2 "$TMP/empty-out.sens" \
  "$BIN/senscore4vykon" --виконати "$ROOT" "$TMP/porozhnie.sens" "$TMP/empty-out.sens"
expect_failure 2 "$TMP/unknown-out.sens" \
  "$BIN/senscore4vykon" --виконати "$ROOT" "$TMP/nevidome.sens" "$TMP/unknown-out.sens"
expect_failure 2 "$TMP/unsupported-out.sens" \
  "$BIN/senscore4vykon" --виконати "$ROOT" "$TMP/nepidtrymano.sens" "$TMP/unsupported-out.sens"
expect_failure 2 "$TMP/absent-out.sens" \
  "$BIN/senscore4vykon" --виконати "$ROOT" "$TMP/nemaie.sens" "$TMP/absent-out.sens"
expect_failure 2 "$TMP/no-root-out.sens" \
  "$BIN/senscore4vykon" --виконати "$TMP" "$TMP/tak.sens" "$TMP/no-root-out.sens"
expect_failure 64 "$TMP/wrong-ext.txt" \
  "$BIN/senscore4vykon" --виконати "$ROOT" "$TMP/tak.sens" "$TMP/wrong-ext.txt"
expect_failure 64 "$TMP/wrong-command.sens" \
  "$BIN/senscore4vykon" --не-виконати "$ROOT" "$TMP/tak.sens" "$TMP/wrong-command.sens"

# Повноцінна послідовність: 3 фізичні Core4-форми, один Core4 runtime.
"$BIN/senscore4vykon" --пакет "$ROOT" \
  "$TMP/paket.sens" "$TMP/paket-result.sens" > "$TMP/stdout" 2>"$TMP/stderr"
cmp "$TMP/paket-chek.sens" "$TMP/paket-result.sens"
grep -q 'форм=3' "$TMP/stdout"
# Одна з наступних форм помилкова: жоден із попередніх результатів не витікає.
expect_failure 2 "$TMP/paket-piznia-out.sens" \
  "$BIN/senscore4vykon" --пакет "$ROOT" \
  "$TMP/paket-piznia-pomylka.sens" "$TMP/paket-piznia-out.sens"
# Діагностика вказує оригінальний фізичний початок ТРЕТЬОЇ форми,
# а не індекс відносно окремо перекодованого виклику.
grep -F -f "$TMP/paket-piznia-adresa.txt" "$TMP/stderr"
grep -F 'помилка фізичної форми' "$TMP/stderr"
expect_failure 2 "$TMP/paket-zavelykyi-out.sens" \
  "$BIN/senscore4vykon" --пакет "$ROOT" \
  "$TMP/paket-zavelykyi.sens" "$TMP/paket-zavelykyi-out.sens"
# Старий режим рівно одного виклику збережено.
expect_failure 2 "$TMP/paket-single-out.sens" \
  "$BIN/senscore4vykon" --виконати "$ROOT" \
  "$TMP/paket.sens" "$TMP/paket-single-out.sens"

cp "$TMP/zainiate.sens" "$TMP/original.sens"
actual=0
"$BIN/senscore4vykon" --виконати "$ROOT" \
  "$TMP/tak.sens" "$TMP/zainiate.sens" >"$TMP/stdout" 2>"$TMP/stderr" || actual=$?
[[ "$actual" -eq 2 ]]
cmp "$TMP/original.sens" "$TMP/zainiate.sens"
test ! -s "$TMP/stdout"
test -s "$TMP/stderr"

# Висяче символьне посилання не задовольняє FileExists(), проте
# існує у каталозі. Старий POSIX RenameFile перезаписував його.
ln -s "$TMP/ніколи-не-створено.sens" "$TMP/висяче.sens"
actual=0
"$BIN/senscore4vykon" --виконати "$ROOT" \
  "$TMP/tak.sens" "$TMP/висяче.sens" >"$TMP/stdout" 2>"$TMP/stderr" || actual=$?
[[ "$actual" -eq 2 ]]
test -L "$TMP/висяче.sens"
[[ "$(readlink "$TMP/висяче.sens")" = "$TMP/ніколи-не-створено.sens" ]]
test ! -e "$TMP/ніколи-не-створено.sens"
test ! -s "$TMP/stdout"
test -s "$TMP/stderr"

# Конкуруючі виконавці одного canonical Core4: рівно один публікує.
for k in 1 2 3 4; do
  dst="$TMP/конкуренція-$k.sens"
  "$BIN/senscore4vykon" --виконати "$ROOT" \
    "$TMP/tak.sens" "$dst" >"$TMP/перший-out" 2>"$TMP/перший-err" &
  first=$!
  "$BIN/senscore4vykon" --виконати "$ROOT" \
    "$TMP/ni.sens" "$dst" >"$TMP/другий-out" 2>"$TMP/другий-err" &
  second=$!
  rc1=0; wait "$first" || rc1=$?
  rc2=0; wait "$second" || rc2=$?
  if [[ "$rc1" -eq 0 && "$rc2" -eq 2 ]]; then
    cmp "$TMP/tak-chek.sens" "$dst"
    test ! -s "$TMP/другий-out"
    test -s "$TMP/другий-err"
  elif [[ "$rc1" -eq 2 && "$rc2" -eq 0 ]]; then
    cmp "$TMP/ni-chek.sens" "$dst"
    test ! -s "$TMP/перший-out"
    test -s "$TMP/перший-err"
  else
    echo "CORE4-CLI-ПОМИЛКА: два процеси претендують на один файл ($rc1,$rc2)" >&2
    exit 1
  fi
done
if find "$TMP" -maxdepth 1 -name 'cr4*' -print -quit | grep -q .; then
  echo 'CORE4-CLI-ПОМИЛКА: після публікації лишився тимчасовий cr4 файл' >&2
  exit 1
fi
echo 'CORE4-CLI-ГАРАЗД FPC=справжній двійкові-виклики=4 негативні=13 пакет=3 атомарний-вихід=так висяче-посилання=захищено конкуренція=4/4 координати=третя-форма'
