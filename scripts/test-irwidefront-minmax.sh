#!/usr/bin/env bash
# G6.138: 11/12 профілі спільного фізичного WideIR, не нові SENS закони.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "Д6-MINMAX-ПРОВАЛ: code=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in timeout fpc git readelf objdump cmp grep mktemp; do
  command -v "$tool" >/dev/null
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(110101 (ук найменше) (укр найменше)' external/sens/lib/domains/d6.lisp
grep -Fq '(110111 (ук найбільше) (укр найбільше)' external/sens/lib/domains/d6.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN="${FPC:-fpc}"
for row in 'src/senswidefrontelf.lpr:senswidefrontelf' \
           'scripts/test-irwidefront-minmax.pas:test-irwidefront-minmax'; do
  IFS=: read -r source name <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
HEAPTRC="log=$TMP/gen.heap" timeout 30s \
  "$TMP/bin/test-irwidefront-minmax" "$TMP/physical" \
  >"$TMP/gen.log" 2>"$TMP/gen.err"
grep -Fq 'D6-MINMAX-FIXTURES positive=24 negative=14' "$TMP/gen.log"
test -s "$TMP/gen.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/gen.heap"
FRONT=--скомпілювати-фізичну-форму
pass=0;oracles=0;minima=0;maxima=0
while IFS=$'\t' read -r label kind a b expected; do
  test -n "$label"
  elf="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 30s \
    "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/physical/$label.sens" "$elf" \
    >"$TMP/$label.out.log" 2>"$TMP/$label.err"
  test -x "$elf"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.out.log"
  readelf -h "$elf" >"$TMP/$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header.log"
  tail -c +121 "$elf" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" \
    >"$TMP/$label.asm.log"
  grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$label.asm.log"
  if [[ "$kind" == 0 ]];then
    grep -Eiq 'cmovg[[:space:]]+eax,ecx' "$TMP/$label.asm.log"
    op=найменше;minima=$((minima+1))
  else
    grep -Eiq 'cmovl[[:space:]]+eax,ecx' "$TMP/$label.asm.log"
    op=найбільше;maxima=$((maxima+1))
  fi
  timeout 5s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3
  timeout 30s "$TMP/bin/senswidefrontelf" "$FRONT" \
    "$TMP/physical/$label.sens" "$TMP/$label.repeat.elf" >/dev/null \
    2>"$TMP/$label.repeat.err"
  cmp "$elf" "$TMP/$label.repeat.elf"
  if [[ -n "$ORACLE" ]];then
    printf '(%s %s %s)\n' "$op" "$a" "$b" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.oracle.expected"
    cmp "$TMP/$label.oracle.log" "$TMP/$label.oracle.expected"
    oracles=$((oracles+1))
  fi
  pass=$((pass+1))
done <"$TMP/physical/cases.tsv"
test "$pass" -eq 24 && test "$minima" -eq 12 && test "$maxima" -eq 12
if [[ -n "$ORACLE" ]];then test "$oracles" -eq 24;fi
neg=0
reject(){
  local output="$TMP/rejected-$neg.elf" rc=0
  timeout 25s "$TMP/bin/senswidefrontelf" "$@" "$output" \
    >"$TMP/negative.log" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/negative.log"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  neg=$((neg+1))
}
for bad in bad-d24-left bad-d24-right bad-d1 bad-d3 bad-d7 \
  bad-arity-one bad-arity-three bad-nested bad-two-roots bad-head \
  bad-truncated bad-root bad-t5m bad-empty;do
  reject "$FRONT" "$TMP/physical/$bad.sens"
done
reject "$FRONT" "$TMP/physical/fake.lisp"
reject "$FRONT" "$TMP/physical/absent.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$neg" -eq 17
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/physical/02.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/missing.elf" "$TMP/symlink.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/physical/02.sens" \
  "$TMP/symlink.elf" >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/symlink.elf" && test ! -e "$TMP/missing.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
  "$TMP/physical/24.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/24.expected.sens"
echo "Д6-MINMAX-МАШИНА-ГАРАЗД profiles=12 min=$minima max=$maxima native-ELF=$pass oracle=$oracles negatives=$neg no-clobber=2 recovered=1 energy=NOT-MEASURED"
# Обов'язкова стара регресія: 16 наявних машинних профілів + їхні відмови.
timeout 1200s bash scripts/test-irwidefront.sh \
  >"$TMP/old.log" 2>"$TMP/old.err" || {
    tail -n 60 "$TMP/old.log" "$TMP/old.err" >&2;exit 1;
  }
grep -Fq 'СПІЛЬНИЙ-WIDEIR-ГАРАЗД physical=16 machine=16' "$TMP/old.log"
