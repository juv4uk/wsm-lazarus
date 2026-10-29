#!/usr/bin/env bash
# G6.125 — канонічний D5 .sens → pinned WideIR → SSE2 PADDQ → D12 T5M.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-SSE2-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in timeout fpc git readelf objdump cmp grep mktemp tail sha256sum; do
  command -v "$t" >/dev/null || {
    echo "Д5-SSE2-БЛОК: відсутній $t" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then
  for log in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 45 "$log" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data" "$TMP/repeat"
for spec in 'scripts/test-elfd12add.pas:test-elfd12add' \
            'scripts/test-irwideaddreg.pas:test-irwideaddreg' \
            'scripts/test-irwideaddsse2.pas:test-irwideaddsse2'; do
  IFS=: read -r src out <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$out" \
    "$ROOT/$src" >"$TMP/$out.build.log" 2>&1 || {
      cat "$TMP/$out.build.log" >&2; exit 1;
    }
done
HEAPTRC="log=$TMP/fixtures.heap" timeout 20s \
  "$TMP/bin/test-elfd12add" "$TMP/data" >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
HEAPTRC="log=$TMP/baseline.heap" timeout 30s \
  "$TMP/bin/test-irwideaddreg" "$TMP/data" >"$TMP/baseline.log" 2>"$TMP/baseline.err" || {
    cat "$TMP/baseline.err" >&2; exit 1;
  }
HEAPTRC="log=$TMP/sse2.heap" timeout 30s \
  "$TMP/bin/test-irwideaddsse2" "$TMP/data" >"$TMP/sse2.log" 2>"$TMP/sse2.err" || {
    cat "$TMP/sse2.err" >&2; exit 1;
  }
grep -Fq 'Д5-SSE2-IR-ГАРАЗД physical=9 machine=9 negative=15 tail=identical' "$TMP/sse2.log"
for heap in fixtures baseline sse2; do
  grep -Fq '0 unfreed memory blocks' "$TMP/$heap.heap"
  test ! -s "$TMP/$heap.err"
done
for i in 01 02 03 04 05 06 07 08 09; do
  file="$TMP/data/$i.sse2.elf"
  chmod 700 "$file"
  timeout 5s readelf -h "$file" >"$TMP/$i.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$i.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$i.header.log"
  timeout 5s readelf -l "$file" >"$TMP/$i.segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$i.segments.log"
  tail -c +121 "$file" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$i.asm.log"
  grep -Eiq 'movd[[:space:]]+xmm8,eax' "$TMP/$i.asm.log"
  grep -Eiq 'movd[[:space:]]+xmm9,ecx' "$TMP/$i.asm.log"
  grep -Eiq 'paddq[[:space:]]+xmm8,xmm9' "$TMP/$i.asm.log"
  grep -Eiq 'movd[[:space:]]+eax,xmm8' "$TMP/$i.asm.log"
  timeout 5s "$file" >"$TMP/$i.actual.sens"
  cmp "$TMP/$i.actual.sens" "$TMP/data/$i-expected.sens"
done
cp "$TMP/data/"*.sens "$TMP/repeat/"
HEAPTRC="log=$TMP/repeat.heap" timeout 30s \
  "$TMP/bin/test-irwideaddsse2" "$TMP/repeat" >"$TMP/repeat.log" 2>"$TMP/repeat.err"
grep -Fq '0 unfreed memory blocks' "$TMP/repeat.heap"
for i in 01 02 03 04 05 06 07 08 09; do
  cmp "$TMP/data/$i.sse2.elf" "$TMP/repeat/$i.sse2.elf"
done
echo 'Д5-SSE2-МАШИНА-ГАРАЗД physical=9 ELF=9 negative=15 deterministic=9 energy=NOT-MEASURED'
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
  oracle=0
  for row in '01:0:0:0' '02:31:42:73' '03:-12:7:-5' \
             '04:-1024:-1024:-2048' '05:-2048:2047:-1' \
             '06:1023:1:1024' '07:2047:-2048:-1' \
             '08:2046:1:2047' '09:-2047:-1:-2048'; do
    IFS=: read -r label a b wanted <<<"$row"
    printf '(додати %s %s)\n' "$a" "$b" >"$TMP/$label.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.oracle.expected"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.oracle.expected"
    oracle=$((oracle+1))
  done
  test "$oracle" -eq 9
  echo "Д5-SSE2-ПІННИЙ-SENS-REPL-ГАРАЗД oracle=$oracle"
fi
