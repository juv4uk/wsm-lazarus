#!/usr/bin/env bash
# G6.113 — host spill: real checked FPC, bytewise GNU as, 2 native ELF,
# plus unchanged verified full D5 .sens → REX → pinned SENS REPL parity.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SPILL-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for bin in timeout fpc git as objcopy cmp readelf objdump grep mktemp; do
  command -v "$bin" >/dev/null || { echo "SPILL-БЛОК: немає $bin" >&2; exit 127; }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 80 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
 -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64spill \
 "$ROOT/scripts/test-x64spill.pas" >"$TMP/fpc.log" 2>&1 || {
   cat "$TMP/fpc.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 40s \
  "$TMP/bin/test-x64spill" "$TMP/data" >"$TMP/spill.log" 2>"$TMP/spill.err" || {
    cat "$TMP/spill.log" "$TMP/spill.err" >&2; exit 1; }
grep -Fq 'X64-SPILL-OK positive=179 negative=14 full-frame=128 elf=2' "$TMP/spill.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
for bit in 0 1; do
  timeout 30s as --64 "$TMP/data/spill-$bit.s" -o "$TMP/spill-$bit.o"
  timeout 30s objcopy -O binary -j .text "$TMP/spill-$bit.o" "$TMP/spill-$bit.gnu.bin"
  cmp "$TMP/spill-$bit.gnu.bin" "$TMP/data/spill-$bit.fpc.bin"
  target="$TMP/data/spill-$bit.elf"
  chmod 700 "$target"
  timeout 5s readelf -h "$target" >"$TMP/header-$bit.log"
  grep -Eq 'Type:.*DYN' "$TMP/header-$bit.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header-$bit.log"
  timeout 5s readelf -l "$target" >"$TMP/segments-$bit.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments-$bit.log"
  tail -c +121 "$target" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" \
    >"$TMP/asm-$bit.log"
  grep -Eq 'mov[[:space:]]+QWORD PTR \[rsp\],rax' "$TMP/asm-$bit.log"
  grep -Eq 'mov[[:space:]]+rax,QWORD PTR \[rsp\]' "$TMP/asm-$bit.log"
  grep -Eq 'movabs[[:space:]]+r15,' "$TMP/asm-$bit.log"
  timeout 5s "$target" >"$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/data/spill-$bit.expected.sens"
done
echo 'SPILL-МАШИНА-ГАРАЗД positive=179 negative=14 elf=2 gnu=2 energy=NOT-MEASURED'
# Differential full D5 authority gate is unchanged and reused as-is.
# Runs 9 real canonical D5 .sens programs and pinned REPL when available.
timeout 900s bash scripts/test-x64lifetimes.sh \
  >"$TMP/pinned-regression.log" 2>"$TMP/pinned-regression.err" || {
    cat "$TMP/pinned-regression.log" "$TMP/pinned-regression.err" >&2; exit 1; }
grep -Fq 'X64-LIFETIMES-МАШИНА-ГАРАЗД intervals=144 rexa=8 native-d5=9 negative=12' \
  "$TMP/pinned-regression.log"
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  grep -Fq 'X64-LIFETIMES-PINNED-REPL-ГАРАЗД oracle=9' "$TMP/pinned-regression.log"
  echo 'SPILL-PINNED-REPL-ГАРАЗД oracle=9'
fi
