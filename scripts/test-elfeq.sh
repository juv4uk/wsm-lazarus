#!/usr/bin/env bash
# G6.13: дійсний ELF64 процес Linux, порівняння із наявним evaluator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'НАТИВНИЙ-EQ-БЛОК: потрібен Linux x86-64' >&2
  exit 1
}
FPC_BIN="$(printenv FPC || echo fpc)"
mkdir -p build/m0.2/elfeq/units build/m0.2/elfeq/bin
for target in test-elfeq senseqelf sensvykon; do
  if [[ "$target" == test-elfeq ]]; then src=scripts/test-elfeq.pas
  else src=src/$target.lpr
  fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/elfeq/units" -FE"$ROOT/build/m0.2/elfeq/bin" \
    -o"$target" "$src"
done
BIN="$ROOT/build/m0.2/elfeq/bin"
"$BIN/test-elfeq"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for label in рівні-0-0 різні-0-1 різні-1-0 рівні-1-1; do
  input="build/m0.2/elfeq/$label.sens"
  "$BIN/senseqelf" --породити "$input" "$TMP/$label.elf" > "$TMP/$label.compile"
  [[ -x "$TMP/$label.elf" ]]
  cmp "build/m0.2/elfeq/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  readelf -l "$TMP/$label.elf" > "$TMP/$label.phdr"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.phdr" >/dev/null
  "$TMP/$label.elf" > "$TMP/$label.machine"
  "$BIN/sensvykon" --виконати "$input" > "$TMP/$label.native"
  cmp "$TMP/$label.machine" "$TMP/$label.native"
  cmp "$TMP/$label.machine" "build/m0.2/elfeq/$label.expected.out"
done
# Відхилені файли не залишають partial stdout чи ELF.
printf '\363' > "$TMP/невірний.sens"
for bad in "$TMP/невірний.sens" "$TMP/немає.sens"; do
  if "$BIN/senseqelf" --породити "$bad" "$TMP/заборонений.elf" \
     >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo 'НАТИВНИЙ-EQ-ТЕСТ-ПОМИЛКА: помилковий вхід прийнято' >&2
    exit 1
  fi
  [[ ! -e "$TMP/заборонений.elf" && ! -s "$TMP/bad.stdout" ]]
  grep -F 'НАТИВНИЙ-EQ-ПОМИЛКА' "$TMP/bad.stderr" >/dev/null
done
printf 'незмінно\n' > "$TMP/існуючий.elf"
if "$BIN/senseqelf" --породити "build/m0.2/elfeq/рівні-0-0.sens" \
   "$TMP/існуючий.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
  echo 'НАТИВНИЙ-EQ-ТЕСТ-ПОМИЛКА: перезаписано ELF' >&2
  exit 1
fi
printf 'незмінно\n' > "$TMP/очікуване"
cmp "$TMP/існуючий.elf" "$TMP/очікуване"
[[ ! -s "$TMP/bad.stdout" ]]
echo 'НАТИВНИЙ-EQ-ELF-ГАРАЗД випадків=4 Linux=справжній D3:101=CMP-SETE двійковий-свідок=зіставлено'
