#!/usr/bin/env bash
# G6.9 — справжнє Linux x86-64 виконання ELF, порівняне з уже злитим senspaket.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'НАТИВНИЙ-D1-ПАКЕТ-БЛОК: потрібен Linux x86-64' >&2
  exit 1
}
FPC_BIN=$(printenv FPC || printf fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'НАТИВНИЙ-D1-ПАКЕТ-БЛОК: немає FPC' >&2; exit 127; }
command -v readelf >/dev/null || { echo 'НАТИВНИЙ-D1-ПАКЕТ-БЛОК: немає readelf' >&2; exit 127; }
mkdir -p build/m0.2/elfd1batch/units build/m0.2/elfd1batch/bin
for target in test-elfd1batch senselfpaket senspaket; do
  case "$target" in
    test-elfd1batch) source=scripts/test-elfd1batch.pas ;;
    *) source="src/$target.lpr" ;;
  esac
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/elfd1batch/units" \
    -FE"$ROOT/build/m0.2/elfd1batch/bin" -o"$target" "$source"
done
BIN="$ROOT/build/m0.2/elfd1batch/bin"
"$BIN/test-elfd1batch"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for label in 'два' 'п’ять' '256'; do
  src="build/m0.2/elfd1batch/$label.sens"
  elf="$TMP/$label.elf"
  "$BIN/senselfpaket" --породити-пакет "$src" "$elf" >"$TMP/$label.compile"
  test -x "$elf"
  cmp "build/m0.2/elfd1batch/$label.expected.elf" "$elf"
  readelf -h "$elf" > "$TMP/$label.elfheader"
  readelf -l "$elf" > "$TMP/$label.elfprogram"
  grep -F 'ELF64' "$TMP/$label.elfheader" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.elfheader" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.elfheader" >/dev/null
  grep -F 'LOAD' "$TMP/$label.elfprogram" >/dev/null
  "$elf" >"$TMP/$label.native"
  "$BIN/senspaket" --пакет "$src" >"$TMP/$label.runtime"
  cmp "$TMP/$label.native" "$TMP/$label.runtime"
done

printf '\363' >"$TMP/зіпсований.sens"
printf 'збережений файл\n' >"$TMP/незмінний.elf"
for src in "$TMP/зіпсований.sens" \
  build/m0.2/elfd1batch/256.sens \
  build/m0.2/elfd1batch/відсутній.sens; do
  if [[ "$src" == build/m0.2/elfd1batch/256.sens ]]; then
    target="$TMP/незмінний.elf"
  else
    target="$TMP/відмова.elf"
  fi
  if "$BIN/senselfpaket" --породити-пакет "$src" "$target" \
       >"$TMP/невдалий.out" 2>"$TMP/невдалий.err"; then
    echo "НАТИВНИЙ-D1-ПАКЕТ-ПОМИЛКА: неприпустимий вихід $target" >&2
    exit 1
  fi
  test ! -s "$TMP/невдалий.out"
  grep -F 'НАТИВНИЙ-D1-ПАКЕТ-ПОМИЛКА' "$TMP/невдалий.err" >/dev/null
  test ! -e "$TMP/відмова.elf"
done
printf 'збережений файл\n' >"$TMP/незмінний.expected"
cmp "$TMP/незмінний.elf" "$TMP/незмінний.expected"
echo 'НАТИВНИЙ-D1-ПАКЕТ-ВИКОНАННЯ-ГАРАЗД FPC=реальний ELF64=x86-64 корені=2,5,256 differential=сенспакет відмова=без-файлу'
