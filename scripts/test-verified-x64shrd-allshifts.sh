#!/usr/bin/env bash
# G6.252 — вичерпний host SHRD: 31 зсув × 8 регістрів × 8 регістрів.
# Доказ використовує вже злитий машинний кодер та незалежний GNU as.
# Автоматичне підключення до чинного test-verified-all.sh без нового CI/apt.
# Немає нового SENS закону, D7/D12+, Rust/Zig, дубльованого ELF чи джоулів.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SHRD-ПОВНА-МАТРИЦЯ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in timeout fpc as objcopy cmp grep mktemp wc; do
  command -v "$tool" >/dev/null || {
    echo "SHRD-ПОВНА-МАТРИЦЯ-БЛОК: немає $tool" >&2
    exit 127
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "SHRD-ПОВНА-МАТРИЦЯ-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ -s "$f" ]] || continue
      echo "--- $f" >&2
      tail -n 45 "$f" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64shrd-allshifts \
  "$ROOT/scripts/test-x64shrd-allshifts.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2
    exit 1
  }
HEAPTRC="log=$TMP/heap.log" timeout 45s \
  "$TMP/bin/test-x64shrd-allshifts" "$TMP/data" \
  >"$TMP/result.log" 2>"$TMP/test.err" || {
    cat "$TMP/result.log" "$TMP/test.err" >&2
    exit 1
  }
grep -Fxq 'G6.252-SHRD-ALLSHIFTS-PASS matrix=1984 bytes=7936 shifts=31 registers=64' "$TMP/result.log"
test ! -s "$TMP/test.err"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test -s "$TMP/data/shrd-full-matrix.s"
test "$(wc -c < "$TMP/data/shrd-full-matrix.fpc.bin")" -eq 7936
timeout 30s as --64 "$TMP/data/shrd-full-matrix.s" -o "$TMP/matrix.o"
timeout 30s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/matrix.gnu.bin"
test "$(wc -c < "$TMP/matrix.gnu.bin")" -eq 7936
cmp "$TMP/data/shrd-full-matrix.fpc.bin" "$TMP/matrix.gnu.bin"
echo 'VERIFIED-SHRD-ALLSHIFTS-PASS checked-FPC=3.2.2 GNU-as=1984 bytes=7936 shifts=31 registers=64 oracle=HOST-ISA energy=NOT-MEASURED'
