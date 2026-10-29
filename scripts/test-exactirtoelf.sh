#!/usr/bin/env bash
# G6.29: реальне Free Pascal -> перевірений ExactIR -> Linux ELF64 -> T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ДОВІРЕНИЙ-IR-ЕЛФ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/exactirtoelf/bin build/m0.2/exactirtoelf/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/exactirtoelf/units" \
  -FE"$ROOT/build/m0.2/exactirtoelf/bin" \
  -otest-exactirtoelf "$ROOT/scripts/test-exactirtoelf.pas"
timeout 30s "$ROOT/build/m0.2/exactirtoelf/bin/test-exactirtoelf" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/exactirtoelf"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in д1-нуль д1-один д3-порожньо д7-син д9-нулі список вкладений; do
  ELF="build/m0.2/exactirtoelf/$label.elf"
  EXPECT="build/m0.2/exactirtoelf/$label.expected.sens"
  test -s "$ELF"
  test -s "$EXPECT"
  chmod u+x "$ELF"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/program"
  grep -F 'ELF64' "$TMP/header" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F 'LOAD' "$TMP/program" >/dev/null
  dd if="$ELF" of="$TMP/code" bs=1 skip=120 count=33 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" > "$TMP/code.asm"
  grep -F 'lea' "$TMP/code.asm" >/dev/null
  grep -F 'rip+' "$TMP/code.asm" >/dev/null
  grep -F 'syscall' "$TMP/code.asm" >/dev/null
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$EXPECT"
done
echo 'ДОВІРЕНИЙ-IR-ЕЛФ-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 ELF=7 T5M=byte-exact'
