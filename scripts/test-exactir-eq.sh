#!/usr/bin/env bash
# G6.30: FPC -> довірений ExactIR -> ELF x86-64 -> фізичний T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ДОВІРЕНИЙ-EQ-IR-БЛОК: потрібна Linux x86-64' >&2;exit 127
}
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/exactireq/bin build/m0.2/exactireq/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/exactireq/units" \
  -FE"$ROOT/build/m0.2/exactireq/bin" \
  -otest-exactir-eq "$ROOT/scripts/test-exactir-eq.pas"
timeout 30s build/m0.2/exactireq/bin/test-exactir-eq \
  "$ROOT/external/sens" "$ROOT/build/m0.2/exactireq"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for n in нуль-нуль нуль-один один-нуль один-один; do
  ELF="build/m0.2/exactireq/$n.elf"
  EXPECT="build/m0.2/exactireq/$n.expected.sens"
  test -s "$ELF"
  test -s "$EXPECT"
  chmod u+x "$ELF"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/program"
  grep -F 'ELF64' "$TMP/header" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F 'LOAD' "$TMP/program" >/dev/null
  objdump -d -M intel "$ELF" > "$TMP/code"
  grep -E 'sete|imul' "$TMP/code" >/dev/null
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$EXPECT"
done
echo 'ДОВІРЕНИЙ-EQ-IR-ФІЗИЧНИЙ-ГАРАЗД ELF64=4 D1=4 machine=виконано T5M=byte-exact'
# Регресія перевіреного G6.29 — попередній IR -> цитата.
timeout 120s bash ./scripts/test-exactirtoelf.sh
