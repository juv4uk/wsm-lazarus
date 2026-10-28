#!/usr/bin/env bash
# G6.8 — виконати справжній ELF64 x86-64 Linux, порівняти із pinned SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -m)" == x86_64 && "$(uname -s)" == Linux ]] || {
  echo 'НАТИВНИЙ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 1;
}
FPC_BIN=${FPC:-fpc}
mkdir -p build/m0.2/elfd1/units build/m0.2/elfd1/bin
for target in test-elfd1 senself sensvykon; do
  if [[ $target == test-elfd1 ]]; then source=scripts/test-elfd1.pas
  else source=src/$target.lpr
  fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/elfd1/units" -FE"$ROOT/build/m0.2/elfd1/bin" \
    -o"$target" "$source"
done
./build/m0.2/elfd1/bin/test-elfd1
BIN="$ROOT/build/m0.2/elfd1/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for bit in 0 1; do
  if [[ $bit == 0 ]]; then label=zero; else label=one; fi
  src="build/m0.2/elfd1/$bit.sens"
  "$BIN/senself" --породити "$src" "$TMP/$label.elf" >"$TMP/$label.compile"
  test -x "$TMP/$label.elf"
  test "$(stat -c %s "$TMP/$label.elf")" = 155
  cmp "build/m0.2/elfd1/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  readelf -l "$TMP/$label.elf" > "$TMP/$label.program"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.program" >/dev/null
  "$TMP/$label.elf" > "$TMP/$label.native"
  "$BIN/sensvykon" --виконати "$src" > "$TMP/$label.reference"
  cmp "$TMP/$label.native" "$TMP/$label.reference"
  printf '%s\n' "$bit" > "$TMP/$label.expected"
  cmp "$TMP/$label.native" "$TMP/$label.expected"
done

# Незалежний машинний ET_DYN, без PT_INTERP, RIP-relative x86-64.
for bit in 0 1; do
  if [[ $bit == 0 ]]; then label=zero; else label=one; fi
  src="build/m0.2/elfd1/$bit.sens"
  "$BIN/senself" --породити-переміщуваний "$src" "$TMP/$label.pie.elf" >"$TMP/$label.pie.compile"
  "$BIN/senself" --породити-переміщуваний "$src" "$TMP/$label.pie.again.elf" >"$TMP/$label.pie.again.compile"
  test -x "$TMP/$label.pie.elf"
  cmp "$TMP/$label.pie.elf" "$TMP/$label.pie.again.elf"
  cmp "build/m0.2/elfd1/$label.expected.elf.pie" "$TMP/$label.pie.elf"
  test "$(stat -c %s "$TMP/$label.pie.elf")" = 155
  readelf -h "$TMP/$label.pie.elf" > "$TMP/$label.pie.header"
  readelf -l "$TMP/$label.pie.elf" > "$TMP/$label.pie.program"
  grep -E 'Type:.*DYN' "$TMP/$label.pie.header" >/dev/null
  grep -E 'Entry point address:.*0x78' "$TMP/$label.pie.header" >/dev/null
  grep -E '^  LOAD[[:space:]]+0x0{16}[[:space:]]+0x0{16}' "$TMP/$label.pie.program" >/dev/null
  if grep -E 'INTERP|DYNAMIC' "$TMP/$label.pie.program" >/dev/null; then
    echo 'НАТИВНИЙ-PIE-ПОМИЛКА: сторонній інтерпретатор ELF' >&2; exit 1
  fi
  "$TMP/$label.pie.elf" > "$TMP/$label.pie.native"
  "$BIN/sensvykon" --виконати "$src" > "$TMP/$label.pie.reference"
  cmp "$TMP/$label.pie.native" "$TMP/$label.pie.reference"
  printf '%s\n' "$bit" > "$TMP/$label.pie.expected"
  cmp "$TMP/$label.pie.native" "$TMP/$label.pie.expected"
done

printf '\363' > "$TMP/bad.sens"
printf 'збережений-файл\n' > "$TMP/existing.elf"
for input in "$TMP/bad.sens" "build/m0.2/elfd1/many.sens" "build/m0.2/elfd1/quote.sens"; do
  if "$BIN/senself" --породити "$input" "$TMP/rejected.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo "НАТИВНИЙ-ELF-ПОМИЛКА: непідтриманий $input став executable" >&2; exit 1
  fi
  test ! -e "$TMP/rejected.elf"
  test ! -s "$TMP/bad.stdout"
  grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА' "$TMP/bad.stderr" >/dev/null
done
# ET_DYN так само зобов'язаний відхиляти непідтриману фізичну SENS
# без побічного ELF-файлу і без часткового stdout.
for input in "$TMP/bad.sens" "build/m0.2/elfd1/many.sens" "build/m0.2/elfd1/quote.sens"; do
  if "$BIN/senself" --породити-переміщуваний "$input" "$TMP/rejected.pie.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo "НАТИВНИЙ-PIE-ПОМИЛКА: непідтриманий $input став executable" >&2; exit 1
  fi
  test ! -e "$TMP/rejected.pie.elf"
  test ! -s "$TMP/bad.stdout"
  grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА' "$TMP/bad.stderr" >/dev/null
done
if "$BIN/senself" --породити build/m0.2/elfd1/0.sens "$TMP/existing.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
  echo 'НАТИВНИЙ-ELF-ПОМИЛКА: перезаписав наявний файл' >&2; exit 1
fi
printf 'збережений-файл\n' > "$TMP/existing.expected"
cmp "$TMP/existing.elf" "$TMP/existing.expected"
test ! -s "$TMP/bad.stdout"
echo 'НАТИВНИЙ-ELF-ВИКОНАННЯ-ГАРАЗД ELF64=x86-64 ET_EXEC=так ET_DYN=так PIE=виконано runtime=машинний D1=0,1 differential=сенсвикон відмова=без-файлу'
