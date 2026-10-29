#!/usr/bin/env bash
# G6.101 — full D2/T5M D6 min/max -> verified WideIR -> executable ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
fault() {
  local rc=$?
  echo "Д6-ЕКСТРЕМУМ-ЗБІЙ рядок=$1 код=$rc" >&2
  for f in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "-- $f" >&2; tail -n 22 "$f" >&2; fi
  done
  exit "$rc"
}
trap 'fault "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for exe in fpc timeout git cmp readelf objdump grep; do command -v "$exe" >/dev/null; done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
git -C external/sens show "$PIN:lib/domains/d6.lisp" |
  grep -F '(110101 (ук найменше) (укр найменше)' >/dev/null
git -C external/sens show "$PIN:lib/domains/d6.lisp" |
  grep -F '(110111 (ук найбільше) (укр найбільше)' >/dev/null
ORACLE=${SENS_ORACLE_BIN:-}
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/фізичні"
for pair in \
  'src/senswideextremaelf.lpr senswideextremaelf' \
  'src/sensd12naimensheelf.lpr sensd12naimensheelf' \
  'src/sensd12naibilsheelf.lpr sensd12naibilsheelf' \
  'src/senschyslo.lpr senschyslo' \
  'scripts/test-irwideextrema.pas test-irwideextrema'; do
  read -r path bin <<<"$pair"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" \
    "$ROOT/$path" >"$TMP/$bin.log" 2>&1 || { cat "$TMP/$bin.log" >&2; exit 1; }
  test -x "$TMP/bin/$bin"
done
timeout 20s "$TMP/bin/test-irwideextrema" "$TMP/фізичні" >"$TMP/gen.log" 2>"$TMP/gen.err"
grep -Fq 'G6.101-FIXTURES-OK cases=32' "$TMP/gen.log"
MODE=--D6-фізичний-екстремум
PASS=0; ORACLE_COUNT=0
while IFS=$'\t' read -r label kind left right expected; do
  test -n "$label"
  elf="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswideextremaelf" "$MODE" \
     "$TMP/фізичні/$label.sens" "$elf" >"$TMP/$label.compile" 2>"$TMP/$label.err"
  test ! -s "$TMP/$label.err"
  grep -Fq 'machine=CMP/CMOV stdout=T5M-D12' "$TMP/$label.compile"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.machine" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.machine" >"$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$label.dis"
  if [[ "$kind" == min ]]; then
    grep -Eiq 'cmov(g|nle)[[:space:]]+eax,ecx' "$TMP/$label.dis"
  else
    grep -Eiq 'cmov(l|nge)[[:space:]]+eax,ecx' "$TMP/$label.dis"
  fi
  # Verify exact machine opcode in image, no reliance on host-computed result.
  if [[ "$kind" == min ]]; then opcode=0f4fc1; op='найменше'; oldmode=--найменше-D12; oldbin=sensd12naimensheelf
  else opcode=0f4cc1; op='найбільше'; oldmode=--найбільше-D12; oldbin=sensd12naibilsheelf; fi
  python3 - "$elf" "$opcode" <<'PY'
from pathlib import Path
import sys
image=Path(sys.argv[1]).read_bytes()
assert image[:4] == bytes.fromhex('7f454c46')
assert bytes.fromhex(sys.argv[2]) in image[120:160], 'missing signed CMOV opcode'
PY
  timeout 10s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/фізичні/$label.expected.sens" "$TMP/$label.actual.sens"
  test "$(wc -c < "$TMP/$label.actual.sens")" -eq 3
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 "$TMP/$label.actual.sens" \
    >"$TMP/$label.ukr"
  printf '%s\n' "$expected" >"$TMP/$label.want"
  cmp "$TMP/$label.want" "$TMP/$label.ukr"
  timeout 20s "$TMP/bin/$oldbin" "$oldmode" \
    "$TMP/фізичні/${label%-*}-l.sens" "$TMP/фізичні/${label%-*}-r.sens" \
    "$TMP/$label.old.elf" >"$TMP/$label.old.out" 2>"$TMP/$label.old.err"
  test ! -s "$TMP/$label.old.err"
  cmp "$elf" "$TMP/$label.old.elf"
  timeout 20s "$TMP/bin/senswideextremaelf" "$MODE" \
    "$TMP/фізичні/$label.sens" "$TMP/$label.repeat.elf" >/dev/null
  cmp "$elf" "$TMP/$label.repeat.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(%s %s %s)\n' "$op" "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    cmp "$TMP/$label.oracle" "$TMP/$label.ukr"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/фізичні/cases.tsv"
test "$PASS" -eq 32
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 32; fi

NEG=0
reject() {
  local rc=0 target="$TMP/reject-$NEG.elf"
  timeout 20s "$TMP/bin/senswideextremaelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 || { echo "Д6-ЕКСТРЕМУМ неправильна відмова код=$rc" >&2; return 1; }
  test ! -e "$target" && test ! -L "$target" && test ! -s "$TMP/negative.out"
  grep -Fq 'Д6-ЕКСТРЕМУМ-ВІДМОВА:' "$TMP/negative.err"
  NEG=$((NEG+1))
}
for bad in bad-d5 bad-d6 bad-d7 bad-arity bad-extra bad-d1 \
  bad-d7arg bad-d24 bad-nested two-roots unclosed root-atom corrupt empty; do
  reject "$MODE" "$TMP/фізичні/$bad.sens"
done
reject "$MODE" "$TMP/фізичні/fake.lisp"
reject "$MODE" "$TMP/фізичні/no-such-file.sens"
reject --вигадано "$TMP/фізичні/01-min.sens"
test "$NEG" -eq 17
cp "$TMP/04-min.elf" "$TMP/protected.elf"
rc=0
timeout 20s "$TMP/bin/senswideextremaelf" "$MODE" "$TMP/фізичні/13-max.sens" \
  "$TMP/protected.elf" >"$TMP/protected.out" 2>"$TMP/protected.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/protected.out"
cmp "$TMP/04-min.elf" "$TMP/protected.elf"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswideextremaelf" "$MODE" "$TMP/фізичні/13-min.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/nonexistent.elf"
timeout 20s "$TMP/bin/senswideextremaelf" "$MODE" "$TMP/фізичні/13-min.sens" \
  "$TMP/recovered.elf" >/dev/null
timeout 10s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/фізичні/13-min.expected.sens" "$TMP/recovered.sens"
echo "Д6-ЕКСТРЕМУМ-ГАРАЗД physical=$PASS oracle=$ORACLE_COUNT negatives=$NEG CMP-CMOV=так byte-identical=так no-clobber=так energy=НЕ-ВИМІРЯНО"
