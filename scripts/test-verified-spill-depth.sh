#!/usr/bin/env bash
# G6.239 — дешевий checked Free Pascal постконтроль spill на 10/50/100.
# Без нового runner/apt/Rust/Zig; чинний verified-all автоматично запускає.
# Це machine IR allocation, не мовний SENS oracle і не вимірювання джоулів.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'SPILL-ГЛИБИНА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in fpc timeout grep mktemp git; do
  command -v "$cmd" >/dev/null || {
    echo "SPILL-ГЛИБИНА-БЛОК: немає $cmd" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc)); then
    echo "SPILL-ГЛИБИНА-ПРОВАЛ code=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err; do
      if [[ -s "$file" ]]; then
        echo "--- $file" >&2; tail -n 50 "$file" >&2
      fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-spill-depth \
  "$ROOT/scripts/test-spill-depth.pas" >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2; exit 1;
  }
test -x "$TMP/bin/test-spill-depth"
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-spill-depth" >"$TMP/actual.log" 2>"$TMP/actual.err"
grep -Fq 'G6.239-SPILL-DEPTH-PASS intervals=170 lengths=10,50,100 rejected=13 frame=16,96,128 oracle=NOT-RUN energy=NOT-MEASURED' "$TMP/actual.log"
test ! -s "$TMP/actual.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
echo 'G6.239-VERIFIED-SPILL-DEPTH-PASS 10/50/100 checked-fpc=YES alien-alias=REJECTED machine-ELF=EXISTING-G6.113 oracle=NOT-RUN energy=NOT-MEASURED'
