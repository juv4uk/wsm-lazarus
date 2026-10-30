#!/usr/bin/env bash
# G6.9 — справжня фізична компіляція і запуск ELF64 x86-64 Linux.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'НАТИВНИЙ-ELF-ПАКЕТ-БЛОК: потрібен Linux x86-64' >&2
  exit 1
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'НАТИВНИЙ-ELF-ПАКЕТ-БЛОК: відсутній Free Pascal' >&2
  exit 127
}
command -v readelf >/dev/null || {
  echo 'НАТИВНИЙ-ELF-ПАКЕТ-БЛОК: відсутній readelf' >&2
  exit 127
}
mkdir -p build/m0.2/elfbatch/units build/m0.2/elfbatch/bin
for target in test-elfbatch senselfpaket senspaket; do
  if [[ "$target" == test-elfbatch ]]; then source=scripts/test-elfbatch.pas
  else source=src/$target.lpr
  fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/elfbatch/units" \
    -FE"$ROOT/build/m0.2/elfbatch/bin" \
    -o"$target" "$source"
done
./build/m0.2/elfbatch/bin/test-elfbatch
BIN="$ROOT/build/m0.2/elfbatch/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for label in alternating separated maximum; do
  physical="build/m0.2/elfbatch/$label.sens"
  "$BIN/senselfpaket" --породити "$physical" "$TMP/$label.elf" >"$TMP/$label.build"
  test -x "$TMP/$label.elf"
  cmp "build/m0.2/elfbatch/$label.expected.elf" "$TMP/$label.elf"
  grep -F 'НАТИВНИЙ-ELF-ПАКЕТ-ГОТОВО' "$TMP/$label.build" >/dev/null
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  readelf -l "$TMP/$label.elf" >"$TMP/$label.program"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.program" >/dev/null
  "$TMP/$label.elf" >"$TMP/$label.native"
  "$BIN/senspaket" --пакет "$physical" >"$TMP/$label.reference"
  cmp "$TMP/$label.native" "$TMP/$label.reference"
  cmp "$TMP/$label.native" "build/m0.2/elfbatch/$label.expected.out"
  "$BIN/senselfpaket" --породити "$physical" "$TMP/$label.repeat.elf" \
    >"$TMP/$label.repeat.build"
  cmp "$TMP/$label.elf" "$TMP/$label.repeat.elf"
done

# Відмова повинна повернути ненульовий статус, без часткового stdout
# і без створеного ELF, незалежно від того, чи це синтаксис або filesystem.
printf '\363' >"$TMP/bad.sens"
: >"$TMP/empty.sens"
printf 'збережений файл\n' >"$TMP/existing.elf"
for label in bad empty missing; do
  if "$BIN/senselfpaket" --породити "$TMP/$label.sens" \
      "$TMP/rejected.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo 'НАТИВНИЙ-ELF-ПАКЕТ-ПОМИЛКА: фізична помилка пропущена' >&2; exit 1
  fi
  test ! -s "$TMP/bad.stdout"
  test ! -e "$TMP/rejected.elf"
  grep -F 'НАТИВНИЙ-ELF-ПАКЕТ-ПОМИЛКА' "$TMP/bad.stderr" >/dev/null
done
if "$BIN/senselfpaket" --породити build/m0.2/elfbatch/alternating.sens \
    "$TMP/existing.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
  echo 'НАТИВНИЙ-ELF-ПАКЕТ-ПОМИЛКА: існуючий файл перезаписано' >&2; exit 1
fi
printf 'збережений файл\n' >"$TMP/existing.expected"
cmp "$TMP/existing.elf" "$TMP/existing.expected"
test ! -s "$TMP/bad.stdout"
for args in "--невідомо build/m0.2/elfbatch/alternating.sens $TMP/z.elf" \
            "--породити build/m0.2/elfbatch/alternating.sens $TMP/z.txt"; do
  # shellcheck disable=SC2086
  if "$BIN/senselfpaket" $args >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo 'НАТИВНИЙ-ELF-ПАКЕТ-ПОМИЛКА: неправильний CLI допущено' >&2; exit 1
  fi
  test ! -s "$TMP/bad.stdout"
  test ! -e "$TMP/z.elf"
  grep -F 'Використання:' "$TMP/bad.stderr" >/dev/null
done
echo 'НАТИВНИЙ-ELF-ПАКЕТ-ВИКОНАННЯ-ГАРАЗД Linux=x86-64 readelf=так коренів=1024 native=так differential=сенспакет негативні=так'
