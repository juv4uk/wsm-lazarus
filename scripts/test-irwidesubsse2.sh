#!/usr/bin/env bash
# G6.128 — pinned D5:01011/WideIR → SSE2 PSUBQ → виконуваний ELF64.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-PSUBQ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc git readelf objdump cmp mktemp grep sha256sum; do
  command -v "$tool" >/dev/null || {
    echo "Д5-PSUBQ-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01011 (ук відняти) (укр відняти)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0 )); then
  for log in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 50 "$log" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for spec in 'scripts/test-irwidesub.pas:test-irwidesub' \
            'scripts/test-irwidesubsse2.pas:test-irwidesubsse2'; do
  IFS=: read -r src exe <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$src" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;
    }
done
HEAPTRC="log=$TMP/fixture.heap" timeout 40s \
  "$TMP/bin/test-irwidesub" "$TMP/physical" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/fixture.log"
HEAPTRC="log=$TMP/psubq.heap" timeout 40s \
  "$TMP/bin/test-irwidesubsse2" "$TMP/physical" \
  >"$TMP/psubq.log" 2>"$TMP/psubq.err"
grep -Fq 'D5-PSUBQ-IR-ГАРАЗД positives=12 negatives=16 D24=4' "$TMP/psubq.log"
for label in fixture psubq; do
  test ! -s "$TMP/$label.err"
  test -s "$TMP/$label.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
done
pass=0;promote=0;oracle=0
while IFS=$'\t' read -r label left right wanted width; do
  [[ -n "$label" ]] || { echo 'Д5-PSUBQ-ВІДМОВА: порожня мітка' >&2; exit 1; }
  elf="$TMP/physical/$label.sse2.elf"
  expected="$TMP/physical/$label.expected.sens"
  test -s "$elf" && test -s "$expected"
  chmod 700 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header.log"
  timeout 5s readelf -l "$elf" >"$TMP/$label.segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.segments.log"
  tail -c +121 "$elf" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$label.asm.log"
  grep -Eiq 'psubq[[:space:]]+xmm8,xmm9' "$TMP/$label.asm.log"
  grep -Eiq 'movd[[:space:]]+eax,xmm8' "$TMP/$label.asm.log"
  hash_before="$(sha256sum "$elf" | cut -d' ' -f1)"
  for repeat in 1 2; do
    timeout 5s "$elf" >"$TMP/$label.$repeat.actual.sens" \
      2>"$TMP/$label.$repeat.machine.err"
    test ! -s "$TMP/$label.$repeat.machine.err"
    cmp "$expected" "$TMP/$label.$repeat.actual.sens"
    test "$(sha256sum "$elf" | cut -d' ' -f1)" = "$hash_before"
  done
  cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
  if [[ "$width" == 24 ]]; then
    test "$(wc -c <"$expected")" -eq 5
    promote=$((promote+1))
  else
    test "$width" = 12
    test "$(wc -c <"$expected")" -eq 3
  fi
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(відняти %s %s)\n' "$left" "$right" >"$TMP/$label.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.wanted"
    cmp "$TMP/$label.wanted" "$TMP/$label.oracle.out"
    oracle=$((oracle+1))
  fi
  pass=$((pass+1))
done <"$TMP/physical/cases.tsv"
test "$pass" -eq 12 && test "$promote" -eq 4
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then test "$oracle" -eq 12; fi
# Загальний firewall ОБОВ'ЯЗКОВИЙ навіть якщо чужий main наразі RED.
timeout 30s bash scripts/check-no-lcl.sh
echo "Д5-PSUBQ-МАШИНА-ГАРАЗД physical=$pass ELF=$pass D24=$promote negatives=16 oracle=$oracle energy=NOT-MEASURED"
