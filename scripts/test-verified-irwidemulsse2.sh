#!/usr/bin/env bash
# G6.242 — pinned SENS D5 → verified WideIR → справжній SSE2 PMULUDQ ELF64.
# Лише стандартний verified-all, без нового workflow та зайвого apt.
set -Eeuo pipefail
trap 'result=$?; echo "SIMD-ДІАГНОСТИКА: line=$LINENO command=$BASH_COMMAND rc=$result" >&2' ERR
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SIMD-МНОЖЕННЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout git readelf objdump cmp grep tail mktemp; do
  command -v "$tool" >/dev/null || {
    echo "SIMD-МНОЖЕННЯ-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp

TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "SIMD-МНОЖЕННЯ-ПРОВАЛ exit=$rc" >&2
    for log in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 40 "$log" >&2; }
    done
    echo "SIMD-ДІАГНОСТИКА: попередній тест" >&2
    if [[ -e "$TMP/original.log" ]]; then tail -n 12 "$TMP/original.log" >&2; fi
    echo "SIMD-ДІАГНОСТИКА: новий SIMD-тест" >&2
    if [[ -e "$TMP/simd.log" ]]; then tail -n 12 "$TMP/simd.log" >&2; fi
    if [[ -s "$TMP/original.err" ]]; then tail -n 12 "$TMP/original.err" >&2; fi
    if [[ -s "$TMP/simd.err" ]]; then tail -n 12 "$TMP/simd.err" >&2; fi
    echo "SIMD-ДІАГНОСТИКА-КІНЕЦЬ rc=$rc" >&2
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"

for row in 'scripts/test-irwidemul.pas:test-irwidemul' \
           'scripts/test-irwidemulsse2.pas:test-irwidemulsse2'; do
  IFS=: read -r path executable <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$path" >"$TMP/$executable.build.log" 2>&1 || {
      tail -n 80 "$TMP/$executable.build.log" >&2; exit 1;
    }
done
HEAPTRC="log=$TMP/original.heap" timeout 60s \
  "$TMP/bin/test-irwidemul" "$TMP/physical" \
  >"$TMP/original.log" 2>"$TMP/original.err"
grep -Fq 'D5-WIDE-MUL-СВІДКИ-ГАРАЗД positives=12 negatives=16' "$TMP/original.log"
HEAPTRC="log=$TMP/simd.heap" timeout 75s \
  "$TMP/bin/test-irwidemulsse2" "$TMP/physical" \
  >"$TMP/simd.log" 2>"$TMP/simd.err"
grep -Fq 'SIMD-PMULUDQ-PASS physical=12 D12=8 D24=4 negatives=5 tail=identical' "$TMP/simd.log"
for item in original simd; do
  test -s "$TMP/$item.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$item.heap"
  test ! -s "$TMP/$item.err"
done

POS=0
D24=0
CLOSED=0
FULL=0
RECOVERY=0
for elf in "$TMP"/physical/*.pmuludq.elf; do
  stem="${elf%.pmuludq.elf}"
  expected="$stem.expected.sens"
  reference="$stem.reference.elf"
  test -s "$elf" && test -s "$expected" && test -s "$reference"
  chmod 700 "$elf" "$reference"
  timeout 5s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$elf" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$elf" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/disasm.log"
  grep -Eiq 'movd[[:space:]]+xmm8,eax' "$TMP/disasm.log"
  grep -Eiq 'movd[[:space:]]+xmm9,ecx' "$TMP/disasm.log"
  grep -Eiq 'pmuludq[[:space:]]+xmm8,xmm9' "$TMP/disasm.log"
  grep -Eiq 'movd[[:space:]]+eax,xmm8' "$TMP/disasm.log"
  timeout 5s "$elf" >"$TMP/result.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$expected" "$TMP/result.sens"
  timeout 5s "$reference" >"$TMP/imul.sens" 2>"$TMP/imul.err"
  test ! -s "$TMP/imul.err"
  cmp "$expected" "$TMP/imul.sens"
  if [[ "$(wc -c <"$expected")" -eq 5 ]]; then D24=$((D24+1)); fi
  POS=$((POS+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$elf" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$elf" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$elf" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
  test ! -s "$TMP/recovery.err"
  cmp "$expected" "$TMP/recovery.sens"
  RECOVERY=$((RECOVERY+1))
done
test "$POS" -eq 12 && test "$D24" -eq 4
test "$CLOSED" -eq 12 && test "$FULL" -eq 12 && test "$RECOVERY" -eq 12
echo "VERIFIED-D5-PMULUDQ-PASS fpc=checked machine=12 d12=8 d24=4 admission-negative=5 closed=12 full=12 recovery=12 pinned-IR=12 oracle=NOT-RUN joules=NOT-MEASURED"
