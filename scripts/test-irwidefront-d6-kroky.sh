#!/usr/bin/env bash
# G6.146 — два точні D6-профілі спільного машинного WideIR.
# Першоджерело мовних законів — pinned external/sens, не цей скрипт.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git fpc timeout readelf objdump cmp mktemp grep awk dd; do
  command -v "$tool" >/dev/null || { echo "потрібен $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
for head in '001110 (ук додати-1) (укр додати-1)' \
            '001111 (ук відняти-1) (укр відняти-1)'; do
  grep -Fq "$head" external/sens/lib/domains/d6.lisp
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.err "$TMP"/*.build; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 45 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-irmixedstep.pas test-irmixedstep' \
  'scripts/test-irwidefront-d6-kroky.pas test-irwidefront-d6-kroky' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senschyslo.lpr senschyslo'; do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2; exit 1;
    }
done
timeout 90s "$TMP/bin/test-irmixedstep" "$TMP" \
  >"$TMP/donor.out" 2>"$TMP/donor.err"
grep -Fxq 'D6-MIXED-UNIT-OK positive=20 negative=17' "$TMP/donor.out"
timeout 90s "$TMP/bin/test-irwidefront-d6-kroky" "$TMP" \
  >"$TMP/frontend.out" 2>"$TMP/frontend.err"
grep -Fxq 'D6-WIDE-FRONT-UNIT-OK physical=20 byte-identical=20 negative=15' \
  "$TMP/frontend.out"
COUNT=0
ORACLE_COUNT=0
ORACLE=$(printenv SENS_ORACLE_BIN || true)
for depth in 1 2 3 4 5; do
  for pattern in 0 1 2 3; do
    tag="$depth-$pattern"
    elf="$TMP/$tag.cli.elf"
    timeout 20s "$TMP/bin/senswidefrontelf" \
      --скомпілювати-фізичну-форму "$TMP/$tag.sens" "$elf" \
      >"$TMP/$tag.compile.out" 2>"$TMP/$tag.compile.err"
    grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$tag.compile.out"
    test -x "$elf"
    cmp "$elf" "$TMP/$tag.frontend.elf"
    cmp "$elf" "$TMP/$tag.elf"
    readelf -h "$elf" >"$TMP/$tag.header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
    readelf -l "$elf" >"$TMP/$tag.segments"
    if grep -Eq 'INTERP|DYNAMIC' "$TMP/$tag.segments"; then
      echo 'неприпустимий динамічний завантажувач' >&2; exit 1
    fi
    timeout 5s "$elf" >"$TMP/$tag.machine.sens" 2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    cmp "$TMP/$tag.expected.sens" "$TMP/$tag.machine.sens"
    test "$(wc -c <"$TMP/$tag.machine.sens")" -eq 3
    dd if="$elf" of="$TMP/$tag.code" bs=1 skip=120 \
      count=$((5+5*depth)) status=none
    objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.code" \
      >"$TMP/$tag.dis"
    grep -Eio '(add|sub)[[:space:]]+eax,' "$TMP/$tag.dis" |
      awk '{print $1}' >"$TMP/$tag.ops"
    : >"$TMP/$tag.expected.ops"
    case "$pattern" in
      0) nested=5 ;;
      1) nested=17 ;;
      2) nested=512 ;;
      3) nested=2040 ;;
    esac
    for ((z=0;z<depth;z++)); do
      if (( pattern==2 || (pattern==0 && z%2==0) ||
                            (pattern==1 && z%2==1) )); then
        printf 'sub\n' >>"$TMP/$tag.expected.ops"
        nested="(відняти-1 $nested)"
      else
        printf 'add\n' >>"$TMP/$tag.expected.ops"
        nested="(додати-1 $nested)"
      fi
    done
    cmp "$TMP/$tag.ops" "$TMP/$tag.expected.ops"
    if [[ -n "$ORACLE" ]]; then
      test -x "$ORACLE"
      test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
      printf '%s\n' "$nested" >"$TMP/$tag.oracle.lisp"
      timeout 60s "$ORACLE" "$TMP/$tag.oracle.lisp" \
        >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
      test ! -s "$TMP/$tag.oracle.err"
      timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
        "$TMP/$tag.machine.sens" >"$TMP/$tag.machine.ukr"
      cmp "$TMP/$tag.oracle.out" "$TMP/$tag.machine.ukr"
      ORACLE_COUNT=$((ORACLE_COUNT+1))
    fi
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 20
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 20; fi
cp "$TMP/1-0.cli.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" \
  --скомпілювати-фізичну-форму \
  "$TMP/1-1.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/1-0.cli.elf"
cp "$TMP/1-0.sens" "$TMP/projection.lisp"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" \
  --скомпілювати-фізичну-форму \
  "$TMP/projection.lisp" "$TMP/forbidden.elf" \
  >"$TMP/forbidden.out" 2>"$TMP/forbidden.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/forbidden.out"
test ! -e "$TMP/forbidden.elf"
echo "Д6-СПІЛЬНИЙ-ELF-ГОТОВО physical=$COUNT machine=$COUNT byte-identical=$COUNT oracle=$ORACLE_COUNT negative=15 no-clobber=так energy=НЕ-ВИМІРЯНО"
