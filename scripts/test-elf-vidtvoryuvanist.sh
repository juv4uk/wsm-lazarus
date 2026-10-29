#!/usr/bin/env bash
# G6.61 — байтова відтворюваність уже наявного ExactIR → ELF64.
# Механічний доказ, не мовна семантика і не новий evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git timeout cmp readelf stat; do
  command -v "$tool" >/dev/null || {
    echo "ЕЛФ-ВІДТВОРЕННЯ-БЛОК: потрібен $tool" >&2
    exit 127
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-ВІДТВОРЕННЯ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
FPC_BIN=$(printenv FPC || printf 'fpc')
command -v "$FPC_BIN" >/dev/null || {
  echo 'ЕЛФ-ВІДТВОРЕННЯ-БЛОК: потрібен справжній FPC' >&2
  exit 127
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/перший" "$TMP/другий"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensmashyna "$ROOT/src/sensmashyna.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-senselfvykon "$ROOT/scripts/test-senselfvykon.pas"
timeout 30s "$TMP/bin/test-senselfvykon" "$TMP"
CLI="$TMP/bin/sensmashyna"
test -x "$CLI"

# Два незалежні виклики host-компілятора: різні cwd, TZ, locale та umask.
# На виході має збігатися ВЕСЬ ELF, не лише stdout, section чи hash.
COUNT=0
for row in \
  'цитата:p01:DYN' 'цитата:p02:DYN' \
  'атом:p03:EXEC' 'атом:p04:EXEC' \
  'тотожність:p05:DYN' 'тотожність:p06:DYN' \
  'селектор:p07:DYN' 'селектор:p08:DYN' \
  'умова:p09:EXEC' 'умова:p10:EXEC' \
  'умова-пі:p09:DYN' 'умова-пі:p10:DYN'; do
  IFS=: read -r profile label kind <<< "$row"
  for attempt in перший другий; do
    if [[ "$attempt" == перший ]]; then
      locale=C
      zone=UTC
      mask=077
    else
      locale=C.UTF-8
      zone=Pacific/Auckland
      mask=022
    fi
    location="$TMP/$attempt"
    executable="$location/$label-$profile.elf"
    (
      cd "$location"
      umask "$mask"
      TZ="$zone" LC_ALL="$locale" timeout 25s "$CLI" "--$profile" \
        "$ROOT/external/sens" "$TMP/$label.sens" "$executable" \
        >"$location/$label-$profile.out" 2>"$location/$label-$profile.err"
    )
    test -x "$executable"
    test "$(stat -c %a "$executable")" = 700
    grep -F 'ELF64-x86-64' "$location/$label-$profile.out" >/dev/null
    grep -F '0 unfreed memory blocks' "$location/$label-$profile.err" >/dev/null
    readelf -h "$executable" >"$location/elf-header"
    readelf -l "$executable" >"$location/elf-program"
    grep -F 'ELF64' "$location/elf-header" >/dev/null
    grep -E "Type:.*$kind" "$location/elf-header" >/dev/null
    grep -F 'Advanced Micro Devices X86-64' "$location/elf-header" >/dev/null
    grep -F 'LOAD' "$location/elf-program" >/dev/null
    timeout 5s "$executable" >"$location/$label-$profile.actual.sens" \
      2>"$location/$label-$profile.machine.err"
    test ! -s "$location/$label-$profile.machine.err"
    cmp "$location/$label-$profile.actual.sens" "$TMP/$label.expected.sens"
  done
  cmp "$TMP/перший/$label-$profile.elf" "$TMP/другий/$label-$profile.elf"
  cmp "$TMP/перший/$label-$profile.actual.sens" \
    "$TMP/другий/$label-$profile.actual.sens"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 12

# Негативи: повний фізичний admission до публікації машинного файла.
REJECTED=0
reject() {
  local name="$1"
  shift
  local target="$TMP/rejected-$name.elf"
  local rc=0
  timeout 15s "$CLI" "$@" "$target" >"$TMP/reject.out" \
    2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "ЕЛФ-ВІДТВОРЕННЯ-ПОМИЛКА: відмова=$name код=$rc" >&2
    exit 1
  }
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.out"
  grep -F 'ELF-ПОМИЛКА' "$TMP/reject.err" >/dev/null
  REJECTED=$((REJECTED+1))
}
cp "$TMP/p01.sens" "$TMP/пізнє-пошкодження.sens"
printf '\363' >>"$TMP/пізнє-пошкодження.sens"
cp "$TMP/p01.sens" "$TMP/підміна.lisp"
reject зіпсований --цитата "$ROOT/external/sens" "$TMP/пізнє-пошкодження.sens"
reject текст --цитата "$ROOT/external/sens" "$TMP/підміна.lisp"
reject д12 --атом "$ROOT/external/sens" "$TMP/d12-atom.sens"
reject хибна-голова --атом "$ROOT/external/sens" "$TMP/p01.sens"
reject відсутній --умова-пі "$ROOT/external/sens" "$TMP/немає.sens"
test "$REJECTED" -eq 5

# Емітер не має права знищувати чужу ціль (включно з dangling symlink).
cp "$TMP/перший/p01-цитата.elf" "$TMP/зайнятий.elf"
rc=0
timeout 15s "$CLI" --цитата "$ROOT/external/sens" "$TMP/p01.sens" \
  "$TMP/зайнятий.elf" >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/зайнятий.elf" "$TMP/перший/p01-цитата.elf"
grep -F 'ELF-ПОМИЛКА' "$TMP/no-clobber.err" >/dev/null
ln -s "$TMP/не-існує.elf" "$TMP/посилання.elf"
rc=0
timeout 15s "$CLI" --цитата "$ROOT/external/sens" "$TMP/p01.sens" \
  "$TMP/посилання.elf" >"$TMP/no-clobber.out" \
  2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
test -L "$TMP/посилання.elf" && test ! -e "$TMP/не-існує.elf"
grep -F 'ELF-ПОМИЛКА' "$TMP/no-clobber.err" >/dev/null
echo "ЕЛФ-ВІДТВОРЕННЯ-ГАРАЗД профілів=$COUNT генерацій=24 відмов=$REJECTED без-перезапису=2 фізичний-stdout=T5M"

# Типи й життя: profile/label — лише host-рядки, не SENS символи;
# $TMP/units має скомпільовані .ppu/.o, приватний каталог і trap
# гарантують очищення; canonical .sens і ELF порівнюються як сирі байти.
# Питання: (1) Чому дві однакові відповіді не доводять однаковий ELF?
# (2) Чому тут немає власного реєстру законів SENS?
# (3) Чому саме повторний емісійний запуск, а не копія ELF?
# (4) Як збережено окрему роль D12 і фізичної D7 проєкції?
# (5) Чому це механічна відтворюваність, а не повний SENS oracle?