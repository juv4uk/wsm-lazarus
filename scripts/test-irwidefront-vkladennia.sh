#!/usr/bin/env bash
# G6.145 — один чинний компілятор для ОБОХ форм вкладення pinned D5.
# Реальні 71 лівих (до 100 кроків) та 36 правих (до 16) ELF64.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for exe in fpc timeout cmp readelf objdump grep git mktemp; do
  command -v "$exe" >/dev/null || { echo "бракує $exe" >&2; exit 127; }
done
TMP="$(mktemp -d)"
finish() {
  local rc=$? f
  if ((rc)); then
    echo "СПІЛЬНИЙ-ВКЛАДЕНИЙ-D5-RED: код=$rc рядок=${BASH_LINENO[0]}" >&2
    for f in "$TMP"/*.build "$TMP"/*.compile.err "$TMP"/*.oracle.err "$TMP"/*.failed; do
      if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 12 "$f" >&2; fi
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
timeout 200s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01010 (ук додати) (укр додати)'
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01011 (ук відняти) (укр відняти)'
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'потрібен pinned незалежний SENS REPL' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
check_heap() {
  local f="$1"
  if grep -Fq 'unfreed memory blocks' "$f"; then
    grep -Fq '0 unfreed memory blocks' "$f" || {
      cat "$f" >&2; return 1;
    }
  fi
}
mkdir -p "$TMP"/{units,bin,left,right,machine}
FPC_BIN="${FPC:-fpc}"
for row in \
  'scripts/test-irarithchain.pas test-irarithchain' \
  'scripts/test-irarithpravy.pas test-irarithpravy' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senschyslo.lpr senschyslo'; do
  read -r source binary <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>&1 || {
      cat "$TMP/$binary.build" >&2; exit 1; }
  test -x "$TMP/bin/$binary"
done
timeout 90s "$TMP/bin/test-irarithchain" "$TMP/left" \
  >"$TMP/left.out" 2>"$TMP/left.err"
grep -Fq 'D5-ARITH-CHAIN-UNIT-OK positive=71 negative=24' "$TMP/left.out"
check_heap "$TMP/left.err"
timeout 90s "$TMP/bin/test-irarithpravy" "$TMP/right" \
  >"$TMP/right.out" 2>"$TMP/right.err"
grep -Fq 'G6.141-RIGHT-D5-UNIT-OK positive=36 negative=16' "$TMP/right.out"
check_heap "$TMP/right.err"

LEFT=0;RIGHT=0;IDENTICAL=0;ORA=0
for direction in left right; do
  for source in "$TMP/$direction"/*.sens; do
    [[ "$source" == *.expected.sens ]] && continue
    tag="${source##*/}"
    tag="${tag%.sens}"
    depth="${tag%%-*}"
    idx="${tag##*-}"
    out="$TMP/machine/$direction-$tag.elf"
    timeout 25s "$TMP/bin/senswidefrontelf" \
      --скомпілювати-фізичну-форму "$source" "$out" \
      >"$TMP/result.out" 2>"$TMP/result.compile.err"
    check_heap "$TMP/result.compile.err"
    grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/result.out"
    test -x "$out"
    timeout 5s readelf -h "$out" >"$TMP/header"
    grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
    ! timeout 5s readelf -l "$out" | grep -Eq 'INTERP|DYNAMIC'
    timeout 5s "$out" >"$TMP/actual.sens" 2>"$TMP/exec.err"
    test ! -s "$TMP/exec.err"
    cmp "$TMP/$direction/$tag.expected.sens" "$TMP/actual.sens"
    test "$(wc -c <"$TMP/actual.sens")" -eq 3
    if ((depth >= 2)); then
      cmp "$TMP/$direction/$tag.elf" "$out"
      IDENTICAL=$((IDENTICAL+1))
    fi
    timeout 25s "$TMP/bin/senswidefrontelf" \
      --скомпілювати-фізичну-форму "$source" \
      "$TMP/machine/$direction-$tag.repeat.elf" \
      > /dev/null 2>"$TMP/repeat.err"
    check_heap "$TMP/repeat.err"
    cmp "$out" "$TMP/machine/$direction-$tag.repeat.elf"
    if [[ -n "$ORACLE" ]]; then
      # Українська .lisp є проєкцією ЛИШЕ для незалежного pinned REPL.
      # Справжній compiler input — фізичні неперекладені байти .sens.
      if [[ "$direction" == left ]]; then
        case "$idx" in
          0) base=-2000;; 1) base=-5;; 2) base=0;;
          3) base=2040;; 4) base=-1473;;
          *) exit 70;;
        esac
        if ((depth>8 && idx==0)); then base=-1900; fi
        right=(3 -7 11 -2)
        nested="$base"
        for ((i=0;i<depth;i++)); do
          if ((i%2==0)); then
            nested="(відняти $nested ${right[i%4]})"
          else
            nested="(додати $nested ${right[i%4]})"
          fi
        done
      else
        case "$idx" in
          0) base=-1900;; 1) base=-7;; 2) base=0;;
          3) base=1200;; *) exit 71;;
        esac
        lefts=(3 -7 11 -2)
        nested="$base"
        for ((i=depth-1;i>=0;i--)); do
          if ((i%2==0)); then
            nested="(додати ${lefts[i%4]} $nested)"
          else
            nested="(відняти ${lefts[i%4]} $nested)"
          fi
        done
      fi
      printf '%s\n' "$nested" >"$TMP/program.lisp"
      timeout 60s "$ORACLE" "$TMP/program.lisp" \
        >"$TMP/oracle.out" 2>"$TMP/oracle.err"
      test ! -s "$TMP/oracle.err"
      timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
        "$TMP/actual.sens" >"$TMP/machine.ukr"
      cmp "$TMP/oracle.out" "$TMP/machine.ukr"
      ORA=$((ORA+1))
    fi
    if [[ "$direction" == left ]]; then LEFT=$((LEFT+1))
    else RIGHT=$((RIGHT+1)); fi
  done
done
test "$LEFT" -eq 71
test "$RIGHT" -eq 36
# Flat 1-step D5 зберігає старий verified backend:
# спеціалізований chain на рівні 1 може мати ІНШИЙ валідний emitter.
# Тільки 99 справді вкладених від 2 рівнів мають byte-identical ELF.
test "$IDENTICAL" -eq 99
if [[ -n "$ORACLE" ]]; then test "$ORA" -eq 107; fi

NEG=0
reject() {
  local rc=0 target="$TMP/machine/invalid-$NEG.elf"
  timeout 25s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/negative.out"
  test ! -e "$target" && test ! -L "$target"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  check_heap "$TMP/negative.err"
  NEG=$((NEG+1))
}
MODE=--скомпілювати-фізичну-форму
printf '\xff' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
head -c -1 "$TMP/left/100-4.sens" >"$TMP/truncated.sens"
cp "$TMP/left/100-4.sens" "$TMP/notcanonical.lisp"
for invalid in "$TMP/corrupt.sens" "$TMP/empty.sens" \
               "$TMP/truncated.sens"; do
  reject "$MODE" "$invalid"
done
reject "$MODE" "$TMP/notcanonical.lisp"
reject "$MODE" "$TMP/missing.sens"
reject --вигадано "$TMP/left/2-1.sens"
test "$NEG" -eq 6
cp "$TMP/machine/left-2-1.elf" "$TMP/occupied.elf"
rc=0
timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/left/2-1.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/machine/left-2-1.elf"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/right/2-1.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/nonexistent.elf"
timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/right/16-1.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/right/16-1.expected.sens" "$TMP/recovered.sens"
echo "G6.145-UNIFIED-NESTED-D5-PASS left=$LEFT right=$RIGHT machine=107 identical_nested=$IDENTICAL oracle=$ORA rejects=$NEG generator_negative=40 no_clobber=2 recovery=1 energy=NOT_MEASURED"
# Старий frontend: усі flat machine профілі й 24 негативи не відключати.
timeout 600s bash scripts/test-irwidefront.sh
