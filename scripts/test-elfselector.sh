#!/usr/bin/env bash
# G6.19 — дійсний FPC 3.2.2 -> ELF64 -> Linux x86-64 виконання CAR/CDR.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИННИЙ-ВИБІР-БЛОК: потрібна Linux x86-64' >&2; exit 127;
}
grep -Fq '(D3:000' external/sens/contracts/language-contract-12.lisp || {
  echo 'МАШИННИЙ-ВИБІР-БЛОК: немає pinned Contract 12' >&2; exit 1;
}
for bits in 011 100 111; do
  grep -Eq "^[[:space:]]*\\($bits \\(ук " external/sens/lib/domains/d3.lisp || {
    echo "МАШИННИЙ-ВИБІР-БЛОК: відсутня точна координата D3:$bits" >&2; exit 1;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
mkdir -p build/m0.2/elfselector/units build/m0.2/elfselector/bin
BIN="$ROOT/build/m0.2/elfselector/bin"
UNITS="$ROOT/build/m0.2/elfselector/units"
for row in 'scripts/test-elfselector.pas test-elfselector' \
  'src/sensvybirelf.lpr sensvybirelf' \
  'src/sensvykon.lpr sensvykon'; do
  read -r SOURCE TARGET <<< "$row"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$UNITS" -FE"$BIN" "-o$TARGET" "$ROOT/$SOURCE"
done
"$BIN/test-elfselector"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in перше-00 перше-01 перше-10 перше-11 \
  решта-00 решта-01 решта-10 решта-11; do
  INPUT="build/m0.2/elfselector/$label.sens"
  "$BIN/sensvybirelf" --породити "$INPUT" "$TMP/$label.elf" >"$TMP/$label.compile"
  test -x "$TMP/$label.elf"
  cmp "build/m0.2/elfselector/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  readelf -l "$TMP/$label.elf" >"$TMP/$label.phdr"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.phdr" >/dev/null
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.machine"
  timeout 10s "$BIN/sensvykon" --виконати "$INPUT" >"$TMP/$label.native"
  cmp "$TMP/$label.machine" "$TMP/$label.native"
  cmp "$TMP/$label.machine" "build/m0.2/elfselector/$label.expected.out"
done
# Реальний pinned binary Core4 відхиляється, не інтерпретується
# за текстовими назвами; підтримується лише вузька фізична форма.
test -s external/sens/lib/core4.sens
if "$BIN/sensvybirelf" --породити external/sens/lib/core4.sens "$TMP/core4.elf" \
  >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННИЙ-ВИБІР-ПОМИЛКА: Core4 без допуску' >&2; exit 1
fi
test ! -s "$TMP/bad.out"
test ! -e "$TMP/core4.elf"
grep -F 'МАШИННИЙ-ВИБІР-ПОМИЛКА' "$TMP/bad.err" >/dev/null
# Канонічний .lisp — тільки людська українська проєкція, не .sens.
if "$BIN/sensvybirelf" --породити external/sens/lib/core4.lisp "$TMP/human.elf" \
  >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННИЙ-ВИБІР-ПОМИЛКА: .lisp помилково прийнято як .sens' >&2
  exit 1
fi
test ! -e "$TMP/human.elf"
test ! -s "$TMP/bad.out"
printf '\363' >"$TMP/invalid.sens"
for bad in invalid.sens missing.sens; do
  if "$BIN/sensvybirelf" --породити "$TMP/$bad" "$TMP/rejected.elf" \
      >"$TMP/bad.out" 2>"$TMP/bad.err"; then
    echo 'МАШИННИЙ-ВИБІР-ПОМИЛКА: недійсний .sens прийнято' >&2; exit 1
  fi
  test ! -e "$TMP/rejected.elf"
  test ! -s "$TMP/bad.out"
  grep -F 'МАШИННИЙ-ВИБІР-ПОМИЛКА' "$TMP/bad.err" >/dev/null
done
printf 'не-перезаписувати\n' >"$TMP/occupied.elf"
cp "$TMP/occupied.elf" "$TMP/unchanged"
if "$BIN/sensvybirelf" --породити build/m0.2/elfselector/перше-00.sens "$TMP/occupied.elf" \
  >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННИЙ-ВИБІР-ПОМИЛКА: перезапис існуючого ELF' >&2; exit 1
fi
cmp "$TMP/occupied.elf" "$TMP/unchanged"
test ! -s "$TMP/bad.out"
echo 'МАШИННИЙ-ВИБІР-ELF-ГАРАЗД D3:100/011 над D3:111 8-машинних-виконань=так pinned-core4=відхилено upstream-REPL=не-доведено'
