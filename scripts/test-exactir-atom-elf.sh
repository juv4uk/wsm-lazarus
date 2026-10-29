#!/usr/bin/env bash
# G6.30 — фізичний ExactIR -> реальний ATOM ELF та регресія цитати.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'СПІЛЬНИЙ-IR-АТОМ-ЕЛФ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
command -v timeout >/dev/null
mkdir -p build/m0.2/iratomelf/bin build/m0.2/iratomelf/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/iratomelf/units" \
  -FE"$ROOT/build/m0.2/iratomelf/bin" \
  -otest-exactir-atom-elf "$ROOT/scripts/test-exactir-atom-elf.pas"
timeout 50s "$ROOT/build/m0.2/iratomelf/bin/test-exactir-atom-elf" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/iratomelf"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in атом-нуль атом-один атом-порожній атом-д3-порожній \
  атом-пара атом-пара-порожній атом-пара-пар \
  атом-вкладений-атом-пари атом-атома атом-вкладена-пара; do
  ELF="build/m0.2/iratomelf/$label.elf"
  EXPECT="build/m0.2/iratomelf/$label.expected.sens"
  test -s "$ELF" && test -s "$EXPECT"
  chmod u+x "$ELF"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/program"
  grep -F ELF64 "$TMP/header" >/dev/null
  grep -E 'Type:.*EXEC' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F LOAD "$TMP/program" >/dev/null
  tail -c +121 "$ELF" > "$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" > "$TMP/disasm"
  grep -F setne "$TMP/disasm" >/dev/null
  grep -F movzx "$TMP/disasm" >/dev/null
  grep -F imul "$TMP/disasm" >/dev/null
  grep -F syscall "$TMP/disasm" >/dev/null
  timeout 5s "$ELF" > "$TMP/actual.sens"
  test "$(wc -c < "$TMP/actual.sens")" -eq 1
  cmp "$TMP/actual.sens" "$EXPECT"
done
echo 'СПІЛЬНИЙ-IR-АТОМ-ЕЛФ-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 ELF=10 T5M=точний'
# Захист G6.29: реальний старий компілятор цитати з тим самим provenance.
bash "$ROOT/scripts/test-exactirtoelf.sh"
