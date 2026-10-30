#!/usr/bin/env bash
# G6.237 — реальний D3:110 ExactIR -> JZ/JMP -> PIE ELF; Linux stdout fail-closed.
# Перевірку автоматично знаходить чинний verified-all на PR; нових workflow немає.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'IR-ПЕРЕХОДИ-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout git readelf objdump cmp mktemp chmod grep tail; do
  command -v "$tool" >/dev/null || {
    echo "IR-ПЕРЕХОДИ-WRITE-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "IR-ПЕРЕХОДИ-WRITE-ПРОВАЛ код=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 35 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-ircondbranch "$ROOT/scripts/test-ircondbranch.pas" \
  >"$TMP/build.log" 2>&1 || {
    tail -n 65 "$TMP/build.log" >&2; exit 1;
  }
test -x "$TMP/bin/test-ircondbranch"
timeout 75s "$TMP/bin/test-ircondbranch" "$TMP/physical" \
  >"$TMP/result.log" 2>"$TMP/heap.err" || {
    cat "$TMP/result.log" "$TMP/heap.err" >&2; exit 1;
  }
grep -Fq 'IR-ПЕРЕХОДИ-ГАРАЗД elfs=13 negative=11' "$TMP/result.log"
if grep -Fq 'unfreed memory blocks' "$TMP/heap.err"; then
  grep -Fq '0 unfreed memory blocks' "$TMP/heap.err"
fi

POS=0
CLOSED=0
FULL=0
RECOVERED=0
for elf in "$TMP"/physical/*.branch.elf; do
  stem="${elf%.branch.elf}"
  expected="$stem.expected.sens"
  source="$stem.sens"
  old="$stem.legacy.elf"
  test -s "$elf" && test -s "$expected" && test -s "$source" && test -s "$old"
  chmod 700 "$elf" "$old"
  timeout 5s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  tail -c +121 "$elf" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm.log"
  grep -Eq 'cmp[[:space:]]+rax,rdx' "$TMP/asm.log"
  grep -Eq 'jne[[:space:]]+' "$TMP/asm.log"
  timeout 5s "$elf" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$expected" "$TMP/actual.sens"
  timeout 5s "$old" >"$TMP/legacy.sens" 2>"$TMP/legacy.err"
  test ! -s "$TMP/legacy.err"
  cmp "$TMP/actual.sens" "$TMP/legacy.sens"
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
  cmp "$expected" "$TMP/recovery.sens"
  test ! -s "$TMP/recovery.err"
  RECOVERED=$((RECOVERED+1))
done
test "$POS" -eq 13 && test "$CLOSED" -eq 13 && \
  test "$FULL" -eq 13 && test "$RECOVERED" -eq 13
echo "VERIFIED-IRCONDBRANCH-WRITE-PASS fpc=checked elf=$POS admission-negatives=11 closed=$CLOSED full=$FULL recovery=$RECOVERED reference=existing-native independent-SENS-oracle=NOT-RUN energy=NOT-MEASURED"
