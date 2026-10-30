#!/usr/bin/env bash
# G6.33: FPC ELF-geometry preflight та справжній Linux ELF64/T5M запуск.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ64-ГЕОМЕТРІЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
command -v timeout >/dev/null
command -v cmp >/dev/null
mkdir -p build/m0.2/elfgeometry/bin build/m0.2/elfgeometry/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/elfgeometry/units" \
  -FE"$ROOT/build/m0.2/elfgeometry/bin" \
  -otest-elfgeometry "$ROOT/scripts/test-elfgeometry.pas"
timeout 60s "$ROOT/build/m0.2/elfgeometry/bin/test-elfgeometry" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/elfgeometry"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in цитата-д7 атом-д1 тотожність-д1 перше-сполучення істинна-умова; do
  ELF="build/m0.2/elfgeometry/$label.elf"
  EXPECT="build/m0.2/elfgeometry/$label.expected.sens"
  test -s "$ELF" && test -s "$EXPECT"
  chmod u+x "$ELF"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/phdr"
  grep -F 'ELF64' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F 'LOAD' "$TMP/phdr" >/dev/null
  tail -c +121 "$ELF" > "$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" > "$TMP/disasm"
  grep -F 'syscall' "$TMP/disasm" >/dev/null
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$EXPECT"
done
echo 'ЕЛФ64-ГЕОМЕТРІЯ-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 реальних-ELF=5 stdout=T5M-byte-exact'
