#!/usr/bin/env bash
# G6.96: незалежні FPC vs GNU as/objcopy; host x86-64, не SENS oracle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ALU-AS-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp mktemp; do
  command -v "$tool" >/dev/null || {
    echo "ALU-AS-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 70 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64alu-as \
  "$ROOT/scripts/test-x64alu-as.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64alu-as" \
  "$TMP/native.bin" "$TMP/reference.s" >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'ALU-AS-ГОТОВО машинних=497 байтів=1058 негативів=5 відновлення=1' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 20s as --64 -o "$TMP/reference.o" "$TMP/reference.s"
timeout 20s objcopy --only-section=.text -O binary "$TMP/reference.o" "$TMP/reference.bin"
test "$(wc -c < "$TMP/native.bin")" -eq 1058
test "$(wc -c < "$TMP/reference.bin")" -eq 1058
cmp "$TMP/native.bin" "$TMP/reference.bin"
echo 'ALU-AS-МАШИНА-ГАРАЗД 497/497 GNU-as байтово тотожні; негативів=5; energy=NOT-MEASURED'
