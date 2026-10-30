#!/usr/bin/env bash
# G6.220: після x86-64 CQO/IDIV справжній Linux write має повернути
# рівно 3 фізичні байти D12/T5M; це host ABI, не новий закон SENS.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д6-ОСТАЧА-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for cmd in fpc timeout readelf objdump cmp dd grep mktemp git; do
  command -v "$cmd" >/dev/null || {
    echo "Д6-ОСТАЧА-WRITE-БЛОК: відсутній $cmd" >&2
    exit 127
  }
done
test -c /dev/full
timeout 90s bash scripts/check-pin.sh
grep -Fq '(010100 (ук остача) (укр остача)' external/sens/lib/domains/d6.lisp
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc != 0)); then
    echo "Д6-ОСТАЧА-WRITE-ПРОВАЛ code=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixtures" "$TMP/свідки"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-cli" -FE"$TMP/bin" \
  -osenswiderestelf "$ROOT/src/senswiderestelf.lpr" \
  >"$TMP/cli.build.log" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-fixtures" -FE"$TMP/bin" \
  -otest-irwiderest "$ROOT/scripts/test-irwiderest.pas" \
  >"$TMP/fixtures.build.log" 2>&1
timeout 35s "$TMP/bin/test-irwiderest" "$TMP/свідки" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'G6.102-REST-FIXTURES-OK cases=28' "$TMP/fixtures.log"
MODE=--скомпілювати-D6-остача-D12
GOOD=0
BAD=0
RECOVERY=0
# 04: (остача 7 3)=1; 18: (остача 7 -3)=-2.
# Очікування — чинні фізичні fixtures, а не другий evaluator.
for label in 04 18; do
  ELF="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswiderestelf" "$MODE" \
    "$TMP/свідки/$label.sens" "$ELF" \
    >"$TMP/$label.compile.log" 2>"$TMP/$label.compile.err"
  test -x "$ELF"
  test ! -s "$TMP/$label.compile.err"
  grep -Fq 'machine=CQO_IDIV_RDX stdout=T5M-D12' "$TMP/$label.compile.log"
  timeout 5s readelf -h "$ELF" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$ELF" of="$TMP/$label.code" bs=1 skip=120 status=none
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'idiv[[:space:]]+rcx' "$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/$label.dis"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/$label.dis"
  timeout 5s "$ELF" >"$TMP/$label.actual.sens" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  cmp "$TMP/свідки/$label.expected.sens" "$TMP/$label.actual.sens"
  test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3
  GOOD=$((GOOD+1))

  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/$label.exec.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.exec.err"
  BAD=$((BAD+1))
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/$label.exec.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.exec.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" >"$TMP/$label.recovery.sens" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  cmp "$TMP/свідки/$label.expected.sens" "$TMP/$label.recovery.sens"
  cmp "$TMP/$label.actual.sens" "$TMP/$label.recovery.sens"
  RECOVERY=$((RECOVERY+1))
done
test "$GOOD" -eq 2 && test "$BAD" -eq 4 && test "$RECOVERY" -eq 2
echo "Д6-ОСТАЧА-WRITE-ГАРАЗД positives=$GOOD negatives=$BAD recovery=$RECOVERY machine=CQO/IDIV/CMP/JNE D12=T5M oracle=NOT-RUN energy=NOT-MEASURED"
