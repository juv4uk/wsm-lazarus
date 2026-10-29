#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'D6-ADD1-ELF-BLOCK: потрібен Linux x86-64' >&2; exit 127; }
for tool in fpc objdump readelf timeout cmp grep sed dd; do command -v "$tool" >/dev/null; done
PROFILE=${SENS_MACHINE_PROFILE:-$ROOT/sens-oracle/lib/machine/profile/current-domain-x86-64.lisp}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
[[ -f "$PROFILE" ]] || { echo 'D6-ADD1-ELF-BLOCK: немає pinned machine profile' >&2; exit 2; }
if [[ -d sens-oracle/.git ]]; then test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"; fi
UNITS="$ROOT/build/g6.81/elfd6add1/units"; BIN="$ROOT/build/g6.81/elfd6add1/bin"; mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -otest-d6add1 "$ROOT/scripts/test-d6add1-elf.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -osensd6add1-elf "$ROOT/src/sensd6add1-elf.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -osenschyslo "$ROOT/src/senschyslo.lpr"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
"$BIN/test-d6add1" "$TMP/cases" >"$TMP/vectors.tsv" 2>"$TMP/unit.stderr"
grep -Fq 'D6-ADD1-UNIT-NEGATIVE-OK cases=5' "$TMP/unit.stderr"
grep -Fq '0 unfreed memory blocks' "$TMP/unit.stderr"
while IFS=$'\t' read -r label value; do
  "$BIN/sensd6add1-elf" "$TMP/cases/$label.sens" "$PROFILE" "$TMP/$label.elf" >"$TMP/$label.publish" 2>"$TMP/$label.stderr"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.stderr"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"; grep -E 'Type:.*DYN' "$TMP/$label.header" >/dev/null
  dd if="$TMP/$label.elf" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 --adjust-vma=0x78 "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'add.*\$0x1,%eax' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.result.sens"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/$label.result.sens"
  "$BIN/senschyslo" --в-укр D12 "$TMP/$label.result.sens" >"$TMP/$label.result.lisp"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    printf '(додати-1 %s)\n' "$value" >"$TMP/$label.expression.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.expression.lisp" >"$TMP/$label.oracle.lisp" 2>"$TMP/$label.oracle.err" || { cat "$TMP/$label.oracle.err" >&2; exit 1; }
    cmp "$TMP/$label.result.lisp" "$TMP/$label.oracle.lisp"
  fi
done <"$TMP/vectors.tsv"
reject() {
  local name=$1 input=$2 profile=${3:-$PROFILE}
  if "$BIN/sensd6add1-elf" "$input" "$profile" "$TMP/$name.elf" >"$TMP/$name.out" 2>"$TMP/$name.err"; then echo "D6-ADD1-ELF-ERROR: прийнято $name" >&2; exit 1; fi
  test ! -e "$TMP/$name.elf"; test ! -s "$TMP/$name.out"; grep -Fq 'ELF-D6-ДОДАТИ-1-ПОМИЛКА:' "$TMP/$name.err"
}
reject wrong-head "$TMP/cases/wrong-head.sens"
reject arity "$TMP/cases/arity.sens"
reject d1 "$TMP/cases/d1.sens"
reject d7 "$TMP/cases/d7.sens"
reject d24 "$TMP/cases/d24.sens"
reject corrupt "$TMP/cases/corrupt.sens"
reject projection "$TMP/cases/projection.lisp"
reject profile-bound "$TMP/cases/profile-bound.sens"
reject overflow "$TMP/cases/overflow.sens"
sed 's/intel-core-i5-6400/not-the-pinned-cpu/' "$PROFILE" >"$TMP/wrong-profile.lisp"
reject wrong-profile "$TMP/cases/zero.sens" "$TMP/wrong-profile.lisp"
cp "$TMP/zero.elf" "$TMP/occupied.elf"
if "$BIN/sensd6add1-elf" "$TMP/cases/zero.sens" "$PROFILE" "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err"; then exit 1; fi
grep -Fq '0 unfreed memory blocks' "$TMP/occupied.err"; cmp "$TMP/zero.elf" "$TMP/occupied.elf"
echo 'D6-ADD1-ELF-OK exact=D6:001110 machine=ADD T5M=exact vectors=4 negatives=10 no-clobber=yes'
