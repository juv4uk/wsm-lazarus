#!/usr/bin/env bash
# G6.229 — структурний D2/VerifiedIR fail-closed, 8 негативів + recovery.
# Автовідкриття чинним verified-all: 0 нових workflow/apt/Rust/Zig.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git grep mktemp tail; do
  command -v "$tool" >/dev/null || {
    echo "VERIFIED-IRHEAD-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh
test -s external/sens/lib/domains/d3.lisp
grep -Fq '(101 (ук тотожне?) (укр тотожне?)' \
  external/sens/lib/domains/d3.lisp
grep -Fq '(000 (ук ()) (укр ())' external/sens/lib/domains/d3.lisp

TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then
  echo "VERIFIED-IRHEAD-ЗБІЙ код=$rc" >&2
  for f in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -35 "$f" >&2; fi
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"

timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-verifiedir-head "$ROOT/scripts/test-verifiedir-head.pas" \
  >"$TMP/build.log" 2>&1 || {
    tail -60 "$TMP/build.log" >&2; exit 1;
  }
test -x "$TMP/bin/test-verifiedir-head"
timeout 60s "$TMP/bin/test-verifiedir-head" "$ROOT/external/sens" \
  >"$TMP/result.log" 2>"$TMP/heap.err" || {
    cat "$TMP/result.log" >&2; cat "$TMP/heap.err" >&2; exit 1;
  }
grep -Fq 'VERIFIED-IRHEAD-PASS positives=9 negatives=8 recovered=8' \
  "$TMP/result.log"
# HeapTrc у FPC 3.2.x друкує 0 unfreed, якщо лічильник не нульовий.
if grep -Fq 'unfreed memory blocks' "$TMP/heap.err"; then
  grep -Fq '0 unfreed memory blocks' "$TMP/heap.err"
fi
cat "$TMP/result.log"
