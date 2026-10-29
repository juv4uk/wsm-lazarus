#!/usr/bin/env bash
# G6.25 — реальний ELF Linux x86-64 має вивести канонічний .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-T5M-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/eqt5m/bin build/m0.2/eqt5m/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src"   -FU"$ROOT/build/m0.2/eqt5m/units"   -FE"$ROOT/build/m0.2/eqt5m/bin"   -otest-elfeqt5m "$ROOT/scripts/test-elfeqt5m.pas"
timeout 30s "$ROOT/build/m0.2/eqt5m/bin/test-elfeqt5m"   "$ROOT/external/sens" "$ROOT/build/m0.2/eqt5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in нуль-нуль нуль-один один-нуль один-один; do
  ELF="build/m0.2/eqt5m/$label.elf"
  test -s "$ELF"
  chmod u+x "$ELF"
  readelf -h "$ELF" >"$TMP/elf-header"
  readelf -l "$ELF" >"$TMP/elf-phdr"
  grep -F 'ELF64' "$TMP/elf-header" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/elf-header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/elf-header" >/dev/null
  grep -F 'LOAD' "$TMP/elf-phdr" >/dev/null
  tail -c +121 "$ELF" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/code.asm"
  grep -F 'sete' "$TMP/code.asm" >/dev/null
  grep -F 'movzx' "$TMP/code.asm" >/dev/null
  grep -F 'imul' "$TMP/code.asm" >/dev/null
  timeout 5s "$ELF" >"$TMP/answer.sens"
  test "$(wc -c <"$TMP/answer.sens")" -eq 1
  cmp "$TMP/answer.sens" "build/m0.2/eqt5m/$label.expected.sens"
done
echo 'ЕЛФ-T5M-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 справжній-ELF=4 CMP/SETE=так T5M=byte-exact негативні=9'
