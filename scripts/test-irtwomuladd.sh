#!/usr/bin/env bash
# G6.125 — two independent D5 IMUL+one ADD, binary-first packed .sens.
# Source oracle receives exactly SAME .sens bytes; host converter is display only.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ДВА-ДОБУТКИ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for p in timeout git fpc readelf objdump cmp mktemp grep dd;do
  command -v "$p" >/dev/null || { echo "ДВА-ДОБУТКИ-БЛОК: бракує $p" >&2;exit 127;}
done
timeout 120s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc != 0));then
    echo "ДВА-ДОБУТКИ-ПРОВАЛ: rc=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.log;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 55 "$f" >&2;}
    done
  fi
  rm -rf "$TMP";exit "$rc"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/cases"
for item in \
  'scripts/test-irtwomuladd.pas:test-irtwomuladd' \
  'src/senstwomuladdelf.lpr:senstwomuladdelf' \
  'src/senschyslo.lpr:senschyslo';do
  IFS=: read -r src exe <<<"$item"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" "$ROOT/$src" \
    >"$TMP/$exe.build.log" 2>&1 || { cat "$TMP/$exe.build.log" >&2;exit 1;}
done
check_heap() {
  if [[ -s "$1" ]];then grep -Fq '0 unfreed memory blocks' "$1";fi
}
HEAPTRC="log=$TMP/generator.heap" timeout 60s \
  "$TMP/bin/test-irtwomuladd" "$TMP/cases" \
  >"$TMP/fixture.out" 2>"$TMP/fixture.err"
grep -Fq 'ДВА-ДОБУТКИ-СВІДКИ-ГАРАЗД positives=14 negatives=20 widened=4' "$TMP/fixture.out"
check_heap "$TMP/generator.heap"
pass=0;widened=0;oracle=0
while IFS=$'\t' read -r label width;do
  [[ -n "$label" ]]
  ELF="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 25s "$TMP/bin/senstwomuladdelf" \
    --скомпілювати-два-множення "$TMP/cases/$label.sens" "$ELF" \
    >"$TMP/$label.status" 2>"$TMP/$label.compile.err"
  test -x "$ELF"
  check_heap "$TMP/$label.heap"
  test ! -s "$TMP/$label.compile.err"
  grep -Fq 'machine=IMUL,IMUL,ADD stdout=T5M' "$TMP/$label.status"
  cmp "$ELF" "$TMP/cases/$label.elf"
  readelf -h "$ELF" >"$TMP/$label.elf.header"
  grep -Eq 'Type:.*DYN' "$TMP/$label.elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.elf.header"
  readelf -l "$ELF" >"$TMP/$label.phdr"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.phdr"
  dd if="$ELF" of="$TMP/$label.prefix" bs=1 skip=120 count=24 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.prefix" >"$TMP/$label.asm"
  test "$(grep -Eic '^ *[0-9a-f]+:.*imul[[:space:]]+(eax|ecx),' "$TMP/$label.asm")" -eq 2
  grep -Eq 'imul[[:space:]]+eax,eax,' "$TMP/$label.asm"
  grep -Eq 'imul[[:space:]]+ecx,ecx,' "$TMP/$label.asm"
  grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/$label.asm"
  timeout 5s "$ELF" >"$TMP/$label.actual.sens" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  cmp "$TMP/$label.actual.sens" "$TMP/cases/$label.expected.sens"
  if [[ "$width" = 24 ]];then
    test "$(wc -c <"$TMP/$label.actual.sens")" -eq 5
    widened=$((widened+1))
  else test "$width" = 12
    test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3
  fi
  if [[ -n "$ORACLE" ]];then
    timeout 60s "$ORACLE" "$TMP/cases/$label.sens" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    timeout 10s "$TMP/bin/senschyslo" --в-укр "D$width" \
      "$TMP/$label.actual.sens" >"$TMP/$label.human"
    cmp "$TMP/$label.human" "$TMP/$label.oracle"
    oracle=$((oracle+1))
  fi
  pass=$((pass+1))
done <"$TMP/cases/cases.tsv"
test "$pass" -eq 14 && test "$widened" -eq 4
if [[ -n "$ORACLE" ]];then test "$oracle" -eq 14;fi

negative=0
reject() {
  local name="$1";shift
  local target="$TMP/rejected-$name.elf" rc=0
  timeout 20s "$TMP/bin/senstwomuladdelf" "$@" "$target" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ДВА-ДОБУТКИ-ELF-ВІДМОВА:' "$TMP/reject.err"
  negative=$((negative+1))
}
for bad in 'чужа-зовнішня-голова' 'чужа-ліва-голова' 'чужа-права-голова' \
  'D6-голова' 'D7-голова' 'лівий-D1' 'правий-D1' \
  'лівий-D24' 'правий-D24' 'ліве-вкладене-недостатня-арність' \
  'праве-вкладене-зайва-арність' 'відсутня-права-гілка' \
  'плоска-форма' 'крапкова-права-гілка' 'два-корені' \
  'незакрито' 'голий-атом' 'неканонічний-T5M' \
  'проміжний-D24-ліворуч' 'проміжний-D24-праворуч';do
  reject "$bad" --скомпілювати-два-множення "$TMP/cases/bad-$bad.sens"
done
test "$negative" -eq 20
cp "$TMP/cases/01.sens" "$TMP/fake.lisp"
: >"$TMP/empty.sens"
reject projection --скомпілювати-два-множення "$TMP/fake.lisp"
reject empty --скомпілювати-два-множення "$TMP/empty.sens"
reject missing --скомпілювати-два-множення "$TMP/absent.sens"
reject wrong-mode --вигадано "$TMP/cases/01.sens"
test "$negative" -eq 24
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senstwomuladdelf" --скомпілювати-два-множення \
  "$TMP/cases/02.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/no-file.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senstwomuladdelf" --скомпілювати-два-множення \
  "$TMP/cases/02.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/no-file.elf" && test -L "$TMP/dangling.elf"
timeout 20s "$TMP/bin/senstwomuladdelf" --скомпілювати-два-множення \
  "$TMP/cases/03.sens" "$TMP/recovered.elf" >"$TMP/recovered.log"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/cases/03.expected.sens"
echo "ДВА-ДОБУТКИ-ГОТОВО real-ELF=$pass widened-D24=$widened negatives=$negative oracle=$oracle no-clobber=2 energy=NOT-MEASURED"
