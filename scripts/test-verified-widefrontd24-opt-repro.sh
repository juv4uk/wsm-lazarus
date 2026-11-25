#!/usr/bin/env bash
# G6.268 — довести, що host-оптимізація FPC не змінює фізичний D24 ELF64.
# Це механічна відтворюваність, не незалежний SENS oracle і не вимір джоулів.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D24-ОПТИМІЗАЦІЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc git timeout mktemp grep cmp readelf stat tail; do
  command -v "$tool" >/dev/null || {
    echo "D24-ОПТИМІЗАЦІЯ-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
finish() {
  local rc=$? f
  if ((rc != 0)); then
    echo "D24-ОПТИМІЗАЦІЯ-ПРОВАЛ code=$rc" >&2
    for f in "$TMP"/*.build.log "$TMP"/*.err "$TMP"/*.log; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/fixtures" "$TMP/fixture-units" "$TMP/fixture-bin"
# Генератор фізичних T5M використовує pinned числову бібліотеку,
# не текстові англійські/українські назви як семантичний dispatch.
timeout 240s fpc -B -Mobjfpc -O1 -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/fixture-units" -FE"$TMP/fixture-bin" \
  '-otest-irwided24carry' "$ROOT/scripts/test-irwided24carry.pas" \
  >"$TMP/fixture.build.log" 2>&1 || {
    tail -n 60 "$TMP/fixture.build.log" >&2; exit 1;
  }
test -x "$TMP/fixture-bin/test-irwided24carry"
HEAPTRC="log=$TMP/fixture.heap" timeout 120s \
  "$TMP/fixture-bin/test-irwided24carry" "$ROOT/external/sens" "$TMP/fixtures" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fq 'IR-D24-CARRY-OK positives=10 negative=12 recovery=1' "$TMP/fixture.log"
test ! -s "$TMP/fixture.err"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"

# Жодні .ppu/.o не переходять із -O1 до -O2: окремі -FU та -FE.
for opt in 1 2; do
  mkdir -p "$TMP/u$opt" "$TMP/bin$opt"
  timeout 240s fpc -B -Mobjfpc "-O$opt" -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u$opt" -FE"$TMP/bin$opt" \
    '-osenswidefrontelf' "$ROOT/src/senswidefrontelf.lpr" \
    >"$TMP/o$opt.build.log" 2>&1 || {
      tail -n 60 "$TMP/o$opt.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin$opt/senswidefrontelf"
done

compiled=0
executed=0
while IFS=$'\t' read -r tag left right expected; do
  [[ "$tag" =~ ^(0[1-9]|10)$ ]] || {
    echo "D24-ОПТИМІЗАЦІЯ: неправильний індекс $tag" >&2; exit 1;
  }
  test -s "$TMP/fixtures/$tag.program.sens"
  for opt in 1 2; do
    ELF="$TMP/$tag.o$opt.elf"
    HEAPTRC="log=$TMP/$tag.o$opt.heap" timeout 50s \
      "$TMP/bin$opt/senswidefrontelf" --скомпілювати-фізичну-форму \
      "$TMP/fixtures/$tag.program.sens" "$ELF" \
      >"$TMP/$tag.o$opt.log" 2>"$TMP/$tag.o$opt.err"
    test ! -s "$TMP/$tag.o$opt.err"
    grep -Fq '0 unfreed memory blocks' "$TMP/$tag.o$opt.heap"
    test "$(stat -c %a "$ELF")" = 700
    timeout 5s "$ELF" >"$TMP/$tag.o$opt.actual.sens" \
      2>"$TMP/$tag.o$opt.exec.err"
    test ! -s "$TMP/$tag.o$opt.exec.err"
    cmp "$TMP/$tag.o$opt.actual.sens" "$TMP/fixtures/$tag.expected.sens"
    executed=$((executed+1))
  done
  cmp "$TMP/$tag.o1.elf" "$TMP/$tag.o2.elf"
  cmp "$TMP/$tag.o1.elf" "$TMP/fixtures/$tag.elf"
  readelf -h "$TMP/$tag.o1.elf" >"$TMP/$tag.elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.elf.header"
  ! readelf -l "$TMP/$tag.o1.elf" | grep -Eq 'INTERP|DYNAMIC'
  compiled=$((compiled+1))
done <"$TMP/fixtures/cases.tsv"
test "$compiled" -eq 10 && test "$executed" -eq 20

# Зламана фізична форма не породжує навіть часткового ELF у жодній збірці.
printf '\377' >"$TMP/corrupt.sens"
negatives=0
for opt in 1 2; do
  rc=0
  timeout 40s "$TMP/bin$opt/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$TMP/corrupt.sens" "$TMP/bad-o$opt.elf" \
    >"$TMP/bad-o$opt.out" 2>"$TMP/bad-o$opt.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/bad-o$opt.out"
  test ! -e "$TMP/bad-o$opt.elf" && test ! -L "$TMP/bad-o$opt.elf"
  grep -Fq 'ВІДМОВА:' "$TMP/bad-o$opt.err"
  negatives=$((negatives+1))
done
# Відмова не отруює наступну компіляцію.
timeout 50s "$TMP/bin2/senswidefrontelf" --скомпілювати-фізичну-форму \
  "$TMP/fixtures/01.program.sens" "$TMP/recovery.elf" \
  >"$TMP/recovery.log" 2>"$TMP/recovery.err"
test ! -s "$TMP/recovery.err"
cmp "$TMP/recovery.elf" "$TMP/01.o1.elf"
timeout 5s "$TMP/recovery.elf" >"$TMP/recovery.actual.sens"
cmp "$TMP/recovery.actual.sens" "$TMP/fixtures/01.expected.sens"
echo "VERIFIED-WIDEFRONT-D24-OPT-PASS FPC=O1+O2 physical=10 byte-identical-ELF=10 executed=20 negatives=$negatives recovery=1 pinned=checked oracle=NOT-RUN energy=NOT-MEASURED"
