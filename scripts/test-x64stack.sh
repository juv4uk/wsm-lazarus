#!/usr/bin/env bash
# G6.102 — checked FPC, незалежний GNU as і реальні ELF64.
# Лише host-механіка, жодних нових законів SENS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export LC_ALL=C.UTF-8 LANG=C.UTF-8

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-СТЕК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for bin in fpc timeout as objcopy cmp readelf mktemp; do
  command -v "$bin" >/dev/null || {
    echo "X64-СТЕК-БЛОК: немає $bin" >&2; exit 127;
  }
done

timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 65 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64stack \
  "$ROOT/scripts/test-x64stack.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-x64stack" "$TMP/data" >"$TMP/test.log" 2>"$TMP/err.log" || {
    cat "$TMP/err.log" "$TMP/test.log" >&2; exit 1;
  }
grep -Fq 'X64-СТЕК-ГОТОВО matrix=45 golden=5 negative=15 recovery=15 elf=2' "$TMP/test.log"

# Байтовий незалежний oracle — assembler, не Pascal і не текстові Dn.
timeout 30s as --64 "$TMP/data/matrix.s" -o "$TMP/matrix.o"
timeout 30s objcopy -O binary --only-section=.text \
  "$TMP/matrix.o" "$TMP/data/matrix.gnu.bin"
cmp "$TMP/data/matrix.fpc.bin" "$TMP/data/matrix.gnu.bin"

for bit in 0 1; do
  elf="$TMP/data/stack-$bit.elf"
  chmod 700 "$elf"
  timeout 15s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s "$elf" >"$TMP/actual-$bit.sens"
  cmp "$TMP/actual-$bit.sens" "$TMP/data/stack-$bit.expected.sens"
done

# Негатив: неправильні host-аргументи не дають успіху.
if timeout 10s "$TMP/bin/test-x64stack" \
  >"$TMP/invalid.out" 2>"$TMP/invalid.err"; then
  echo 'X64-СТЕК-БЛОК: відсутній аргумент не відхилено' >&2
  exit 1
fi
test ! -s "$TMP/invalid.out"
test -s "$TMP/invalid.err"
echo 'X64-СТЕК-ПЕРЕВІРЕНО матриця=45 GNU-as=байтово 15-негативів=атомарно ELF=2 T5M=точно energy=NOT-MEASURED'
