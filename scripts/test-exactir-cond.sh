#!/usr/bin/env bash
# G6.37 — справжній Linux x86-64 ELF64 з перевіреної фізичної ExactIR.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ДОВІРЕНА-УМОВА-IR-БЛОК: потрібна Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null

# Оригінальний G6.28 згенерує й дійсно виконає дев'ять фізичних
# .sens/ELF/expected.sens без зміни жодного його файла.
timeout 150s bash ./scripts/test-elfcondt5m.sh
BASE="$ROOT/build/m0.2/elfcondt5m/witnesses"
OUT="$ROOT/build/m0.2/exactircond"
mkdir -p "$OUT/units" "$OUT/bin" "$OUT/verified"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-exactir-cond "$ROOT/scripts/test-exactir-cond.pas"
timeout 45s "$OUT/bin/test-exactir-cond" \
  "$ROOT/external/sens" "$BASE" "$OUT/verified"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
count=0
for fixture in "$BASE"/*.sens; do
  [[ "$fixture" == *.expected.sens || "$fixture" == *.actual.sens ]] && continue
  stem=${fixture%.sens}
  name=${stem##*/}
  machine="$OUT/verified/$name.elf"
  test -s "$machine"
  cmp "$machine" "$stem.elf"
  chmod u+x "$machine"
  readelf -h "$machine" > "$TMP/header"
  readelf -l "$machine" > "$TMP/program"
  grep -F 'ELF64' "$TMP/header" >/dev/null
  grep -E 'Type:.*EXEC' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F LOAD "$TMP/program" >/dev/null
  tail -c +121 "$machine" > "$TMP/code.bin"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code.bin" > "$TMP/disasm"
  grep -F jne "$TMP/disasm" >/dev/null || [[ "$name" == вичерпання ]]
  grep -F syscall "$TMP/disasm" >/dev/null
  timeout 5s "$machine" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$stem.expected.sens"
  test "$(wc -c < "$TMP/actual.sens")" -eq 1
  count=$((count+1))
done
test "$count" -eq 9
echo 'ДОВІРЕНА-УМОВА-IR-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 ELF=9 exact=T5M'
# Регресія: той самий provenance guard обслуговує попередні D3 backend.
timeout 150s bash ./scripts/test-exactir-eq.sh
timeout 150s bash ./scripts/test-exactir-atom-elf.sh
echo 'ДОВІРЕНА-УМОВА-IR-РЕГРЕСІЯ-ГАРАЗД D3=001/010/101/110'
