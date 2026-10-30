#!/usr/bin/env bash
# G6: механічна верифікація BSF/BSR. Це НЕ нові закони SENS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'BSF-BSR-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc as objcopy readelf objdump cmp mktemp; do
  command -v "$tool" >/dev/null || { echo "BSF-BSR-БЛОК: немає $tool" >&2; exit 127; }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then
  for f in "$TMP"/*.log; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 65 "$f" >&2; }
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64bitscan \
  "$ROOT/scripts/test-x64bitscan.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 35s \
  "$TMP/bin/test-x64bitscan" "$TMP/data" >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'BSF-BSR-ГОТОВО golden=2 negative=4 quota=256 recovery=1 gnu=128 elf=2' "$TMP/test.log"
test ! -s "$TMP/stderr.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log" || {
  cat "$TMP/heap.log" >&2; exit 1;
}
timeout 40s as --64 "$TMP/data/matrix.s" -o "$TMP/matrix.o"
timeout 20s objcopy -O binary --only-section=.text "$TMP/matrix.o" "$TMP/matrix.gnu.bin"
test "$(wc -c < "$TMP/matrix.gnu.bin")" -eq 384
cmp "$TMP/data/matrix.fpc.bin" "$TMP/matrix.gnu.bin"
for name in first last; do
  elf="$TMP/data/$name.elf"
  chmod 700 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$elf" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$elf" >"$TMP/machine.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/disassembly.log"
  if [[ "$name" == first ]]; then
    grep -Eq '\bbsf\b' "$TMP/disassembly.log"
  else
    grep -Eq '\bbsr\b' "$TMP/disassembly.log"
  fi
  timeout 5s "$elf" >"$TMP/answer.sens" 2>"$TMP/answer.stderr"
  test ! -s "$TMP/answer.stderr"
  cmp "$TMP/answer.sens" "$TMP/data/$name.sens"
done
echo 'BSF-BSR-МАШИНА-ГАРАЗД oracle=128 negatives=4 ELF64=2 physical=T5M energy=NOT-MEASURED'
