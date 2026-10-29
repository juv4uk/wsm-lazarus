#!/usr/bin/env bash
# G6.151 — 22 фізичні D5:10111/D12 дають ті самі реальні ELF64 за FPC -O1/-O2.
# Не доказ загального компілятора чи виміряних джоулів.
# 1) Чому перевіряємо байти ELF? 2) Чому .sens не .lisp?
# 3) Чому потрібен окремий oracle? 4) Де заборонено перезапис?
# 5) Що доводять дві різні збірки FPC?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for bin in timeout fpc git cmp readelf mktemp grep wc; do
  command -v "$bin" >/dev/null || { echo "БЛОК: немає $bin" >&2; exit 127; }
done
TMP="$(mktemp -d)"
cleanup() {
  code=$?
  if ((code)); then
    echo "ЕЛЬФ-ВІДТВОРЕННЯ-RED code=$code" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 18 "$f" >&2; fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Fq '0 unfreed memory blocks' "$1" || { cat "$1" >&2; return 1; }
  fi
}
timeout 180s bash scripts/sync-authority.sh
timeout 60s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
ORACLE_BIN="${SENS_ORACLE_BIN:-}"
REQUIRE="${REQUIRE_SENS_ORACLE:-0}"
if [[ "$REQUIRE" == 1 ]]; then
  [[ -n "$ORACLE_BIN" && -x "$ORACLE_BIN" ]] || { echo 'НЕМАЄ-SENS-ORACLE' >&2; exit 127; }
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/fixtures" "$TMP/ug" "$TMP/bg"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/ug" -FE"$TMP/bg" -otest-irwidequot \
  "$ROOT/scripts/test-irwidequot.pas" >"$TMP/gen.build" 2>&1 || {
  cat "$TMP/gen.build" >&2; exit 1;
}
timeout 40s "$TMP/bg/test-irwidequot" "$TMP/fixtures" >"$TMP/gen.out" 2>"$TMP/gen.err"
check_heap "$TMP/gen.err"
test "$(wc -l < "$TMP/fixtures/cases.tsv")" -eq 22
# Окремі -FU шляхи унеможливлюють повторне використання .ppu.
for opt in 1 2; do
  mkdir -p "$TMP/u$opt" "$TMP/b$opt"
  timeout 180s fpc -B -O"$opt" -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u$opt" -FE"$TMP/b$opt" -osenswidefrontelf \
    "$ROOT/src/senswidefrontelf.lpr" >"$TMP/o$opt.build" 2>&1 || {
    cat "$TMP/o$opt.build" >&2; exit 1;
  }
  test -x "$TMP/b$opt/senswidefrontelf"
done
MODE=--скомпілювати-фізичну-форму
COUNT=0; MATCH=0
while IFS=$'\t' read -r label decimal; do
  [[ -n "$label" && -n "$decimal" ]]
  for opt in 1 2; do
    elf="$TMP/$label-$opt.elf"
    timeout 30s "$TMP/b$opt/senswidefrontelf" "$MODE" \
      "$TMP/fixtures/$label.sens" "$elf" >"$TMP/compiler.out" 2>"$TMP/compiler.err"
    check_heap "$TMP/compiler.err"
    grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/compiler.out"
    test -x "$elf"
    timeout 10s readelf -h "$elf" >"$TMP/header"
    grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
    timeout 10s "$elf" >"$TMP/result.sens" 2>"$TMP/native.err"
    test ! -s "$TMP/native.err"
    cmp "$TMP/result.sens" "$TMP/fixtures/$label.expected.sens"
  done
  cmp "$TMP/$label-1.elf" "$TMP/$label-2.elf"
  if [[ -n "$ORACLE_BIN" ]]; then
    printf '(частка %s %s)\n' "$decimal" "$decimal" >"$TMP/oracle.lisp"
    timeout 60s "$ORACLE_BIN" "$TMP/oracle.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    printf '1\n' >"$TMP/expected.out"
    cmp "$TMP/oracle.out" "$TMP/expected.out"
    MATCH=$((MATCH+1))
  fi
  COUNT=$((COUNT+1))
done <"$TMP/fixtures/cases.tsv"
test "$COUNT" -eq 22
if [[ "$REQUIRE" == 1 ]]; then test "$MATCH" -eq 22; fi
timeout 30s "$TMP/b2/senswidefrontelf" "$MODE" \
  "$TMP/fixtures/01.sens" "$TMP/repeat.elf" >/dev/null 2>"$TMP/repeat.err"
check_heap "$TMP/repeat.err"
cmp "$TMP/repeat.elf" "$TMP/01-1.elf"
NEGATIVE=0
for opt in 1 2; do
  for bad in bad-t5m empty wrong-width two-roots; do
    target="$TMP/bad-$opt-$bad.elf"; status=0
    timeout 30s "$TMP/b$opt/senswidefrontelf" "$MODE" \
      "$TMP/fixtures/$bad.sens" "$target" >"$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
    test "$status" -eq 2
    test ! -e "$target" && test ! -L "$target" && test ! -s "$TMP/reject.out"
    grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/reject.err"
    check_heap "$TMP/reject.err"
    NEGATIVE=$((NEGATIVE+1))
  done
  status=0
  timeout 30s "$TMP/b$opt/senswidefrontelf" "$MODE" \
    "$TMP/fixtures/fake.lisp" "$TMP/fake-$opt.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
  test "$status" -eq 2 && test ! -e "$TMP/fake-$opt.elf"
  test ! -s "$TMP/reject.out"
  NEGATIVE=$((NEGATIVE+1))
  cp "$TMP/01-1.elf" "$TMP/occupied-$opt.elf"
  status=0
  timeout 30s "$TMP/b$opt/senswidefrontelf" "$MODE" \
    "$TMP/fixtures/02.sens" "$TMP/occupied-$opt.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
  test "$status" -eq 2 && test ! -s "$TMP/reject.out"
  cmp "$TMP/01-1.elf" "$TMP/occupied-$opt.elf"
  NEGATIVE=$((NEGATIVE+1))
done
test "$NEGATIVE" -eq 12
echo "ЕЛЬФ-ВІДТВОРЕННЯ-PASS O1=$COUNT O2=$COUNT same=$COUNT oracle=$MATCH negative=$NEGATIVE energy=NOT-MEASURED"
