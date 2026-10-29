#!/usr/bin/env bash
# G6.35 — справжній FPC -> допуск ELF64 -> атомарна публікація.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ПУБЛІКАЦІЯ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p build/m0.2/elfpublish/units build/m0.2/elfpublish/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/elfpublish/units" \
  -FE"$ROOT/build/m0.2/elfpublish/bin" \
  -otest-elfpublish "$ROOT/scripts/test-elfpublish.pas"
timeout 45s "$ROOT/build/m0.2/elfpublish/bin/test-elfpublish" \
  "$ROOT/external/sens" "$TMP"

# Регресія чинного 8-профільного CLI (реальний FPC, x86, 11 негативів).
timeout 120s bash "$ROOT/scripts/test-sensmashyna.sh"
# Регресія незалежного структурного ELF admission (36 фізичних мутацій).
timeout 120s bash "$ROOT/scripts/test-elfgeometry.sh"

CLI="$ROOT/build/m0.2/mashyna/bin/sensmashyna"
for entry in \
  'цитата:d3-001:physical-001' \
  'атом:d3-010:physical-010' \
  'тотожність:d3-101:physical-101'; do
  IFS=: read -r mode label source <<< "$entry"
  ELF="$TMP/cli-$label.elf"
  timeout 10s "$CLI" "--$mode" "$ROOT/external/sens" \
    "$TMP/$source.sens" "$ELF" > "$TMP/cli-output"
  cmp "$ELF" "$TMP/$label.elf"
  readelf -h "$ELF" > "$TMP/elf-header"
  readelf -l "$ELF" > "$TMP/elf-segment"
  grep -F ELF64 "$TMP/elf-header" >/dev/null
  grep -F LOAD "$TMP/elf-segment" >/dev/null
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/$label.expected.sens"
done

# POSIX O_EXCL: неперезапис реальної цілі та dangling symlink.
cp "$TMP/d3-001.elf" "$TMP/existing.elf"
if timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
  "$TMP/physical-001.sens" "$TMP/existing.elf" \
  >"$TMP/out" 2>"$TMP/err"; then
  echo 'ПУБЛІКАЦІЯ-ПРОВАЛ: дозволено перезапис наявного ELF' >&2; exit 1
fi
cmp "$TMP/existing.elf" "$TMP/d3-001.elf"
test ! -s "$TMP/out"
ln -s "$TMP/missing-object.elf" "$TMP/dangling.elf"
if timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
  "$TMP/physical-001.sens" "$TMP/dangling.elf" \
  >"$TMP/out" 2>"$TMP/err"; then
  echo 'ПУБЛІКАЦІЯ-ПРОВАЛ: дозволено підміну символьного посилання' >&2; exit 1
fi
test -L "$TMP/dangling.elf"
test ! -e "$TMP/missing-object.elf"
test ! -s "$TMP/out"

# G6.36: жодного нового SENS закону чи machine emitter.
# Повторно використовуємо незалежні фізичні свідки наявних 8 selector
# та 9 cond backend. Кожний новий CLI ELF РЕАЛЬНО запускається.
timeout 120s bash "$ROOT/scripts/test-elfselectort5m.sh"
timeout 120s bash "$ROOT/scripts/test-elfcondt5m.sh"
SEL="$ROOT/build/m0.2/selectort5m"
COND="$ROOT/build/m0.2/elfcondt5m/witnesses"
ADDED=0
for label in перше-00 перше-01 перше-10 перше-11 \
             решта-00 решта-01 решта-10 решта-11; do
  filename="$TMP/вивід-селектор-$ADDED.elf"
  timeout 10s "$CLI" --селектор "$ROOT/external/sens" \
    "$SEL/$label.sens" "$filename"
  test -x "$filename"
  cmp "$filename" "$SEL/$label.elf"
  readelf -h "$filename" >"$TMP/header"
  readelf -l "$filename" >"$TMP/segments"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F LOAD "$TMP/segments" >/dev/null
  timeout 5s "$filename" >"$TMP/машинна-відповідь.sens"
  cmp "$TMP/машинна-відповідь.sens" "$SEL/$label.expected.sens"
  cmp "$TMP/машинна-відповідь.sens" "$SEL/$label.native.sens"
  ADDED=$((ADDED+1))
done
for label in вичерпання істинна-одиниця істинний-нуль хибна-умова \
             друга-гілка рівність-істина рівність-хиба \
             рівність-у-тесті рівність-не-обрана; do
  filename="$TMP/вивід-умова-$ADDED.elf"
  timeout 10s "$CLI" --умова "$ROOT/external/sens" \
    "$COND/$label.sens" "$filename"
  test -x "$filename"
  cmp "$filename" "$COND/$label.elf"
  readelf -h "$filename" >"$TMP/header"
  readelf -l "$filename" >"$TMP/segments"
  grep -Eq 'Type:.*EXEC' "$TMP/header"
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F LOAD "$TMP/segments" >/dev/null
  timeout 5s "$filename" >"$TMP/машинна-відповідь.sens"
  cmp "$TMP/машинна-відповідь.sens" "$COND/$label.expected.sens"
  test "$(wc -c <"$TMP/машинна-відповідь.sens")" -eq 1
  ADDED=$((ADDED+1))
done
test "$ADDED" -eq 17

# Перед будь-яким файловим записом неправильні exact форми/профілі
# мусять відхилятися без ELF, stdout чи прихованого fallback.
ADDED_NEG=0
reject_extended() {
  local target="$TMP/негатив-$ADDED_NEG.elf"
  if timeout 12s "$CLI" "$1" "$ROOT/external/sens" "$2" "$target" \
    >"$TMP/stdout" 2>"$TMP/stderr"; then
    echo 'МАШИННИЙ-CLI-ПОМИЛКА: прийнято заборонений профіль' >&2
    exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/stdout"
  # FPC host codepage може вивести українські glyph як '?';
  # перевіряємо незмінну ASCII-частину того самого fault-маркера.
  grep -F 'ELF-' "$TMP/stderr" >/dev/null
  ADDED_NEG=$((ADDED_NEG+1))
}
reject_extended --умова "$SEL/перше-00.sens"
reject_extended --селектор "$COND/вичерпання.sens"
reject_extended --умова "$TMP/хибний-д12.sens"
reject_extended --селектор "$TMP/хибний-д12.sens"
reject_extended --умова "$TMP/помилковий-байт.sens"
reject_extended --селектор "$TMP/помилковий-байт.sens"
reject_extended --умова "$TMP/фальшивий.lisp"
reject_extended --селектор "$TMP/фальшивий.lisp"
test "$ADDED_NEG" -eq 8
# Повторно перевіряємо no-clobber саме для нових профілів,
# включно з dangling symlink без цільового inode.
cp "$COND/істинна-одиниця.elf" "$TMP/старий-вміст.elf"
cp "$TMP/старий-вміст.elf" "$TMP/недоторканий.elf"
if timeout 10s "$CLI" --умова "$ROOT/external/sens" \
  "$COND/істинна-одиниця.sens" "$TMP/недоторканий.elf" \
  >"$TMP/stdout" 2>"$TMP/stderr"; then
  echo 'МАШИННИЙ-CLI-ПОМИЛКА: перезаписано існуючий ELF-умови' >&2; exit 1
fi
cmp "$TMP/недоторканий.elf" "$TMP/старий-вміст.elf"
test ! -s "$TMP/stdout"
ln -s "$TMP/відсутній-вузол.elf" "$TMP/захищене-посилання.elf"
if timeout 10s "$CLI" --селектор "$ROOT/external/sens" \
  "$SEL/перше-00.sens" "$TMP/захищене-посилання.elf" \
  >"$TMP/stdout" 2>"$TMP/stderr"; then
  echo 'МАШИННИЙ-CLI-ПОМИЛКА: перезаписано dangling symlink' >&2; exit 1
fi
test -L "$TMP/захищене-посилання.elf"
test ! -e "$TMP/відсутній-вузол.elf"
test ! -s "$TMP/stdout"

echo 'ДВА-НОВІ-ФАЙЛОВІ-ELF-ГАРАЗД selector=8 cond=9 ET_DYN=8 ET_EXEC=9 негативні=8 no-clobber=так T5M=побайтово'
echo 'ПЕРЕВІРЕНА-ПУБЛІКАЦІЯ-ELF-ФІЗИЧНИЙ-ГАРАЗД CLI=5 регресія-CLI=8 геометрія=36 no-clobber=так машинний-T5M=побайтово'
