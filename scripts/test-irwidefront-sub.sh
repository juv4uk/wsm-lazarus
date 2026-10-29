#!/usr/bin/env bash
# G6.115: сьомий профіль одного компілятора; 12 canonical D5 SUB,
# 4 справжніх D24, 18 негативів + 6 CLI; 6 старих профілів не змінюються.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'СІМ-ПРОФІЛІВ-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for cmd in fpc git timeout cmp grep readelf objdump mktemp; do
  command -v "$cmd" >/dev/null || { echo "СІМ-ПРОФІЛІВ-БЛОК: немає $cmd" >&2;exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01011 (ук відняти) (укр відняти)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
done_run() {
  local rc=$?
  if ((rc != 0));then
    echo "СІМ-ПРОФІЛІВ-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 45 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap done_run EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in 'scripts/test-irwidesub.pas:test-irwidesub' \
           'scripts/test-irwidefront-sub.pas:test-irwidefront-sub' \
           'src/senswidefrontelf.lpr:senswidefrontelf' \
           'src/senswidesubelf.lpr:senswidesubelf';do
  IFS=: read -r source exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2;exit 1; }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/gen.heap" timeout 30s \
  "$TMP/bin/test-irwidesub" "$TMP/physical" >"$TMP/gen.log" 2>"$TMP/gen.err"
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/gen.log"
grep -Fq '0 unfreed memory blocks' "$TMP/gen.heap"
HEAPTRC="log=$TMP/verify.heap" timeout 30s \
  "$TMP/bin/test-irwidefront-sub" "$TMP/physical" >"$TMP/verify.log" 2>"$TMP/verify.err"
grep -Fq 'SEVEN-WIDEIR-SUB-OK positive=12 D24=4 negative=18 images=identical' "$TMP/verify.log"
grep -Fq '0 unfreed memory blocks' "$TMP/verify.heap"
FRONT=--скомпілювати-фізичну-форму
SPECIAL=--скомпілювати-віднімання-Д5
passed=0
wide=0
oracle_count=0
while IFS=$'\t' read -r label left right wanted width;do
  test -n "$label"
  output="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 20s \
    "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/physical/$label.sens" "$output" \
    >"$TMP/$label.status.log" 2>"$TMP/$label.err"
  test -x "$output"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  test ! -s "$TMP/$label.err"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.status.log"
  timeout 20s "$TMP/bin/senswidesubelf" "$SPECIAL" \
    "$TMP/physical/$label.sens" "$TMP/$label.special.elf" \
    >"$TMP/$label.special.log" 2>"$TMP/$label.special.err"
  cmp "$output" "$TMP/$label.special.elf"
  cmp "$output" "$TMP/physical/$label.reference.elf"
  readelf -h "$output" >"$TMP/$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header.log"
  readelf -l "$output" >"$TMP/$label.program.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.program.log"
  tail -c +121 "$output" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$label.asm.log"
  grep -Eq 'sub[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$label.asm.log"
  timeout 5s "$output" >"$TMP/$label.actual.sens"
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  if [[ "$width" = 24 ]];then
    test "$(wc -c <"$TMP/$label.actual.sens")" -eq 5
    wide=$((wide+1))
  else test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3;fi
  if [[ -n "$ORACLE" ]];then
    printf '(відняти %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.wanted"
    cmp "$TMP/$label.oracle.log" "$TMP/$label.wanted"
    oracle_count=$((oracle_count+1))
  fi
  passed=$((passed+1))
done <"$TMP/physical/cases.tsv"
test "$passed" -eq 12 && test "$wide" -eq 4
if [[ -n "$ORACLE" ]];then test "$oracle_count" -eq 12;fi

bad=0
reject() {
  local label="$1";shift
  local output="$TMP/rejected-$label.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$output" \
    >"$TMP/bad.out" 2>"$TMP/bad.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/bad.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/bad.err"
  bad=$((bad+1))
}
cp "$TMP/physical/01.sens" "$TMP/fake.lisp"
printf '\377' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
reject unsupported "$FRONT" "$TMP/physical/front-unsupported.sens"
reject text "$FRONT" "$TMP/fake.lisp"
reject corrupt "$FRONT" "$TMP/corrupt.sens"
reject empty "$FRONT" "$TMP/empty.sens"
reject absent "$FRONT" "$TMP/absent.sens"
reject wrong-mode --вигадано "$TMP/physical/01.sens"
test "$bad" -eq 6

cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
 "$TMP/physical/02.sens" "$TMP/occupied.elf" >"$TMP/occupied.out" \
  2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/no-file.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
 "$TMP/physical/03.sens" "$TMP/dangling.elf" >"$TMP/dangling.out" \
  2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/no-file.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
 "$TMP/physical/03.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/03.expected.sens"

# Без послаблень повністю перевірити попередні 6 профілів:
# 9 ADD, 12 MUL, 16 старих, 24 негативи і oracle за наявності.
timeout 1000s bash scripts/test-irwidefront-aryfmetyka.sh \
  >"$TMP/old-six.log" 2>"$TMP/old-six.err"
grep -Fq 'ШІСТЬ-ПРОФІЛІВ-ГОТОВО add=9 mul=12' "$TMP/old-six.log"
echo "SEVEN-WIDEIR-SUB-DONE positive=$passed D24=$wide oracle=$oracle_count negative=$((18+bad)) previous=6 energy=NOT-MEASURED"
