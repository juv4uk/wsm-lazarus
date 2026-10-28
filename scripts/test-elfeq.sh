#!/usr/bin/env bash
# G6.13 — дійсні x86-64 інструкції D3:101, pinned SENS як закон.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИННА-ТОТОЖНІСТЬ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
mkdir -p build/m0.2/elfeq/units build/m0.2/elfeq/bin
BIN="$ROOT/build/m0.2/elfeq/bin"
UNITS="$ROOT/build/m0.2/elfeq/units"
for row in 'scripts/test-elfeq.pas test-elfeq' 'src/senseqelf.lpr senseqelf' \
  'src/sensvykon.lpr sensvykon' 'src/senst5m.lpr senst5m'; do
  read -r SOURCE TARGET <<< "$row"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$UNITS" -FE"$BIN" "-o$TARGET" "$ROOT/$SOURCE"
done
"$BIN/test-elfeq"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in тотожні-нулі нуль-один один-нуль тотожні-одиниці; do
  INPUT="build/m0.2/elfeq/$label.sens"
  "$BIN/senseqelf" --породити "$INPUT" "$TMP/$label.elf" > "$TMP/$label.compile"
  test -x "$TMP/$label.elf"
  cmp "build/m0.2/elfeq/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  readelf -l "$TMP/$label.elf" > "$TMP/$label.phdr"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.phdr" >/dev/null
  timeout 5s "$TMP/$label.elf" > "$TMP/$label.machine"
  timeout 10s "$BIN/sensvykon" --виконати "$INPUT" > "$TMP/$label.native"
  cmp "$TMP/$label.machine" "$TMP/$label.native"
  cmp "$TMP/$label.machine" "build/m0.2/elfeq/$label.expected.out"
done
# Той самий машинний CMP/SETE виконується тепер і як ET_DYN.
# Не підміняти це перевіркою самих ELF-заголовків: запуск обов'язковий.
for label in тотожні-нулі нуль-один один-нуль тотожні-одиниці; do
  INPUT="build/m0.2/elfeq/$label.sens"
  "$BIN/senseqelf" --породити-переміщуваний "$INPUT" "$TMP/$label.pie.elf" > "$TMP/$label.pie.compile"
  "$BIN/senseqelf" --породити-переміщуваний "$INPUT" "$TMP/$label.pie.again.elf" > "$TMP/$label.pie.again.compile"
  test -x "$TMP/$label.pie.elf"
  cmp "$TMP/$label.pie.elf" "$TMP/$label.pie.again.elf"
  cmp "build/m0.2/elfeq/$label.expected.elf.pie" "$TMP/$label.pie.elf"
  readelf -h "$TMP/$label.pie.elf" > "$TMP/$label.pie.header"
  readelf -l "$TMP/$label.pie.elf" > "$TMP/$label.pie.phdr"
  grep -E 'Type:.*DYN' "$TMP/$label.pie.header" >/dev/null
  grep -E 'Entry point address:.*0x78' "$TMP/$label.pie.header" >/dev/null
  grep -E '^  LOAD[[:space:]]+0x0{16}[[:space:]]+0x0{16}' "$TMP/$label.pie.phdr" >/dev/null
  if grep -E 'INTERP|DYNAMIC' "$TMP/$label.pie.phdr" >/dev/null; then
    echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: сторонній завантажувач PIE' >&2
    exit 1
  fi
  timeout 5s "$TMP/$label.pie.elf" > "$TMP/$label.pie.machine"
  timeout 10s "$BIN/sensvykon" --виконати "$INPUT" > "$TMP/$label.pie.native"
  cmp "$TMP/$label.pie.machine" "$TMP/$label.pie.native"
  cmp "$TMP/$label.pie.machine" "build/m0.2/elfeq/$label.expected.out"
done

# Pinned неіграшковий SENS EQ-свідок: точні .sens + біти + укр .lisp.
UPSTREAM="$ROOT/external/sens"
PIN=$(git -C "$UPSTREAM" rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
[[ "$PIN" == "$GITLINK" ]] || { echo 'МАШИННА-ТОТОЖНІСТЬ-БЛОК: pin drift' >&2; exit 1; }
STEM='tests/semantic/d3-eq-atom-boundary-law'
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM.sens" > "$TMP/root.sens"
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM" > "$TMP/root.words"
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM.lisp" > "$TMP/root.lisp"
test -s "$TMP/root.sens"
test -s "$TMP/root.lisp"
grep -F 'тотожне?' "$TMP/root.lisp" >/dev/null
"$BIN/senst5m" --перегляд "$TMP/root.sens" > "$TMP/root.decoded"
cmp "$TMP/root.words" "$TMP/root.decoded"
# Саме ЦЕ pinned .lisp містить складну умову; наша 2xD1 машинна
# підмножина зобов'язана ВІДХИЛИТИ її, не створивши псевдо-доказ.
if "$BIN/senseqelf" --породити "$TMP/root.sens" "$TMP/root.elf" \
    > "$TMP/pinned.bad.out" 2>"$TMP/pinned.bad.err"; then
  echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: неуповноважений pinned EQ закон допущено' >&2
  exit 1
fi
test ! -e "$TMP/root.elf"
test ! -s "$TMP/pinned.bad.out"
grep -F 'НАТИВНЕ-ЕКВІВАЛЕНТНЕ-ПОМИЛКА' "$TMP/pinned.bad.err" >/dev/null

# Непідтверджений pinned EQ-свідок не може породити й PIE.
if "$BIN/senseqelf" --породити-переміщуваний "$TMP/root.sens" "$TMP/root.pie.elf" \
    > "$TMP/pinned.pie.out" 2> "$TMP/pinned.pie.err"; then
  echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: pinned форма пройшла PIE без допуску' >&2
  exit 1
fi
test ! -e "$TMP/root.pie.elf"
test ! -s "$TMP/pinned.pie.out"
grep -F 'НАТИВНЕ-ЕКВІВАЛЕНТНЕ-ПОМИЛКА' "$TMP/pinned.pie.err" >/dev/null

# Порушена фізика, відсутній файл та неправильна проєкція.
printf '\363' > "$TMP/invalid.sens"
for bad in invalid.sens missing.sens; do
  if "$BIN/senseqelf" --породити "$TMP/$bad" "$TMP/reject.elf" \
      > "$TMP/bad.out" 2>"$TMP/bad.err"; then
    echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: некоректний .sens допущено' >&2; exit 1
  fi
  test ! -e "$TMP/reject.elf"
  test ! -s "$TMP/bad.out"
  grep -F 'НАТИВНЕ-ЕКВІВАЛЕНТНЕ-ПОМИЛКА' "$TMP/bad.err" >/dev/null
done
if "$BIN/senseqelf" --породити "$TMP/root.lisp" "$TMP/invalid.elf" \
  > "$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: .lisp трактовано як двійковий .sens' >&2; exit 1
fi
test ! -s "$TMP/bad.out"
test ! -e "$TMP/invalid.elf"

for bad in invalid.sens missing.sens; do
  if "$BIN/senseqelf" --породити-переміщуваний "$TMP/$bad" "$TMP/reject.pie.elf" \
      > "$TMP/bad.pie.out" 2> "$TMP/bad.pie.err"; then
    echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: пошкоджений .sens породив PIE' >&2; exit 1
  fi
  test ! -e "$TMP/reject.pie.elf"
  test ! -s "$TMP/bad.pie.out"
done
if "$BIN/senseqelf" --породити-переміщуваний "$TMP/root.lisp" "$TMP/invalid.pie.elf" \
    > "$TMP/bad.pie.out" 2> "$TMP/bad.pie.err"; then
  echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: текст став фізичною програмою PIE' >&2; exit 1
fi
test ! -e "$TMP/invalid.pie.elf"
test ! -s "$TMP/bad.pie.out"

printf 'не-перезаписувати\n' > "$TMP/occupied.elf"
cp "$TMP/occupied.elf" "$TMP/original"
if "$BIN/senseqelf" --породити 'build/m0.2/elfeq/тотожні-нулі.sens' "$TMP/occupied.elf" \
 > "$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: перезаписано наявний ELF' >&2; exit 1
fi
cmp "$TMP/occupied.elf" "$TMP/original"
if "$BIN/senseqelf" --породити-переміщуваний 'build/m0.2/elfeq/тотожні-нулі.sens' "$TMP/occupied.elf" \
    > "$TMP/bad.pie.out" 2> "$TMP/bad.pie.err"; then
  echo 'МАШИННА-ТОТОЖНІСТЬ-ПОМИЛКА: PIE перезаписав файл' >&2; exit 1
fi
cmp "$TMP/occupied.elf" "$TMP/original"
test ! -s "$TMP/bad.pie.out"
test ! -s "$TMP/bad.out"
echo "МАШИННА-ТОТОЖНІСТЬ-ГАРАЗД pin=$PIN ELF64=x86-64 ET_EXEC=так ET_DYN=так D3:101=CMP/SETE чотири-пари=фізично-перевірені pinned-sens-ukr=звірені повний-SENS-REPL=не-доведено"
