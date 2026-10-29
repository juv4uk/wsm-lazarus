#!/usr/bin/env bash
# G6.97: реальний dynamic D12 stdin → TEST/SETE → exact D1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-ПОТІК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in timeout fpc mktemp readelf objdump cmp grep tail stat dd head seq; do
  command -v "$cmd" >/dev/null || {
    echo "Д12-ПОТІК-БЛОК: немає $cmd" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then for f in "$TMP/build.log" "$TMP/run.log" "$TMP/heap.log"; do if [[ -s "$f" ]]; then tail -n 70 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd12zeropotik "$ROOT/scripts/test-elfd12zeropotik.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-elfd12zeropotik" \
  "$TMP/data" >"$TMP/run.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/run.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'D12-STREAM-BUILD-OK elf=1 vectors=12' "$TMP/run.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
STREAM="$TMP/data/stream.elf"
chmod 700 "$STREAM"
readelf -h "$STREAM" >"$TMP/elfheader"
grep -Eq 'Type:.*DYN' "$TMP/elfheader"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elfheader"
readelf -l "$STREAM" >"$TMP/elfsegments"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/elfsegments"
tail -c +121 "$STREAM" >"$TMP/code"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/code" >"$TMP/disasm"
grep -Eiq 'test[[:space:]]+r8d,r8d' "$TMP/disasm"
grep -Eiq 'sete[[:space:]]+al' "$TMP/disasm"
PASS=0
for n in $(seq -w 0 11); do
  chmod 700 "$TMP/data/$n.elf"
  timeout 5s "$STREAM" <"$TMP/data/$n.sens" >"$TMP/got.sens" 2>"$TMP/error"
  test ! -s "$TMP/error"
  cmp "$TMP/got.sens" "$TMP/data/$n.expected.sens"
  timeout 5s "$TMP/data/$n.elf" >"$TMP/old.sens"
  cmp "$TMP/got.sens" "$TMP/old.sens"
  PASS=$((PASS+1))
done
test "$PASS" -eq 12
NEG=0
reject() {
  if timeout 5s "$STREAM" <"$1" >"$TMP/reject.out" 2>"$TMP/reject.err"; then
    echo 'Д12-ПОТІК-ПОМИЛКА: помилковий T5M допущено' >&2; exit 1
  else
    rc=$?
    test "$rc" -eq 2 || { echo "неправильний код відмови: $rc" >&2; exit 1; }
  fi
  test ! -s "$TMP/reject.out"
  grep -Fq 'Д12-ПОТІК-ВІДМОВА' "$TMP/reject.err"
  NEG=$((NEG+1))
}
: >"$TMP/empty"; reject "$TMP/empty"
head -c 1 "$TMP/data/00.sens" >"$TMP/short1"; reject "$TMP/short1"
head -c 2 "$TMP/data/00.sens" >"$TMP/short2"; reject "$TMP/short2"
cp "$TMP/data/00.sens" "$TMP/surplus"; printf '\000' >>"$TMP/surplus"; reject "$TMP/surplus"
cp "$TMP/data/00.sens" "$TMP/invalid"; printf '\377' | dd of="$TMP/invalid" bs=1 seek=2 conv=notrunc status=none; reject "$TMP/invalid"
cp "$TMP/data/00.sens" "$TMP/badpadding"; printf '\000' | dd of="$TMP/badpadding" bs=1 seek=2 conv=notrunc status=none; reject "$TMP/badpadding"
cp "$TMP/data/00.sens" "$TMP/badfirst"; printf '\377' | dd of="$TMP/badfirst" bs=1 seek=0 conv=notrunc status=none; reject "$TMP/badfirst"
{ head -c 1 "$TMP/data/00.sens"; sleep 0.05;
  tail -c +2 "$TMP/data/00.sens"; } | timeout 5s "$STREAM" >"$TMP/chunked.sens"
cmp "$TMP/chunked.sens" "$TMP/data/00.expected.sens"
test "$NEG" -eq 7
echo "Д12-ПОТІК-МАШИНА-ГАРАЗД vectors=$PASS negative=$NEG chunked=1 test-sete=yes energy=NOT-MEASURED"
