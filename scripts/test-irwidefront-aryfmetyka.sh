#!/usr/bin/env bash
# G6.107 — єдиний frontend розширено З ЧОТИРЬОХ ДО ШЕСТИ machine profiles.
# .sens (packed T5M) → pinned exact WideIR → чинний додати/помножити.
# Чотири старі профілі зберігають незмінні фізичні регресійні свідки.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'ШІСТЬ-ПРОФІЛІВ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for bin in fpc git timeout cmp grep readelf objdump tail mktemp; do
  command -v "$bin" >/dev/null || { echo "НЕМАЄ ІНСТРУМЕНТА: $bin" >&2; exit 127; }
done
timeout 120s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
report() {
  local rc=$?
  if ((rc != 0)); then
    echo "ШІСТЬ-ПРОФІЛІВ-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.build.log "$TMP"/*.err "$TMP"/*.oracle.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 60 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap report EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/add" "$TMP/mul" "$TMP/bad"
# ЄДИНІ перевірені backend-CLI залишаються незмінними та служать
# побайтовим golden для нового спільного вхідного механізму.
for row in \
  'scripts/test-elfd12add.pas:test-elfd12add' \
  'scripts/test-irwideaddreg.pas:test-irwideaddreg' \
  'scripts/test-irwidemul.pas:test-irwidemul' \
  'scripts/test-irwidefront.pas:test-irwidefront' \
  'src/senswidefrontelf.lpr:senswidefrontelf' \
  'src/senswideaddregelf.lpr:senswideaddregelf' \
  'src/senswidemulelf.lpr:senswidemulelf'; do
  IFS=: read -r src exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$src" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1; }
  test -x "$TMP/bin/$exe"
done
check_heap() {
  local log="$1"
  test -s "$log"
  grep -Fq '0 unfreed memory blocks' "$log" || {
    echo "ВИТІК У $log" >&2;cat "$log" >&2; return 1; }
}
HEAPTRC="log=$TMP/first.heap" timeout 30s \
  "$TMP/bin/test-elfd12add" "$TMP/add" >"$TMP/first.out" 2>"$TMP/first.err"
HEAPTRC="log=$TMP/add.heap" timeout 30s \
  "$TMP/bin/test-irwideaddreg" "$TMP/add" >"$TMP/add.out" 2>"$TMP/add.err"
HEAPTRC="log=$TMP/mul.heap" timeout 30s \
  "$TMP/bin/test-irwidemul" "$TMP/mul" >"$TMP/mul.out" 2>"$TMP/mul.err"
HEAPTRC="log=$TMP/bad.heap" timeout 30s \
  "$TMP/bin/test-irwidefront" "$TMP/bad" >"$TMP/bad.out" 2>"$TMP/bad.err"
for h in first add mul bad;do check_heap "$TMP/$h.heap";done
grep -Fq 'Д5-РЕЄСТРИ-СВІДКИ-ГАРАЗД physical=9 identical=9 negative=15' "$TMP/add.out"
grep -Fq 'D5-WIDE-MUL-СВІДКИ-ГАРАЗД positives=12 negatives=16' "$TMP/mul.out"
grep -Fq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/bad.out"

FRONT=--скомпілювати-фізичну-форму
ADD=--скомпілювати-додавання-Д5
MUL=--скомпілювати-множення-Д5
success=0;widened=0;oracle_count=0
verify_case() {
  local label="$1" kind="$2" source="$3" wanted="$4" left="$5" right="$6" value="$7" width="$8"
  local output="$TMP/$kind-$label.elf" old="$TMP/$kind-$label.special.elf"
  HEAPTRC="log=$TMP/$kind-$label.heap" timeout 25s \
    "$TMP/bin/senswidefrontelf" "$FRONT" "$source" "$output" \
    >"$TMP/$kind-$label.out" 2>"$TMP/$kind-$label.err"
  test -x "$output"
  check_heap "$TMP/$kind-$label.heap"
  test ! -s "$TMP/$kind-$label.err"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$kind-$label.out"
  if [[ "$kind" = add ]]; then
    timeout 25s "$TMP/bin/senswideaddregelf" "$ADD" "$source" "$old" \
      >"$TMP/$kind-$label.special.log" 2>"$TMP/$kind-$label.special.err"
  else
    timeout 25s "$TMP/bin/senswidemulelf" "$MUL" "$source" "$old" \
      >"$TMP/$kind-$label.special.log" 2>"$TMP/$kind-$label.special.err"
  fi
  cmp "$output" "$old"
  readelf -h "$output" >"$TMP/$kind-$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$kind-$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$kind-$label.header.log"
  readelf -l "$output" >"$TMP/$kind-$label.segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$kind-$label.segments.log"
  tail -c +121 "$output" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$kind-$label.dis.log"
  if [[ "$kind" = add ]]; then
    grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/$kind-$label.dis.log"
  else
    grep -Eq 'imul[[:space:]]+eax,eax,' "$TMP/$kind-$label.dis.log"
  fi
  timeout 5s "$output" >"$TMP/$kind-$label.actual.sens"
  cmp "$TMP/$kind-$label.actual.sens" "$wanted"
  if [[ "$kind" = mul && "$width" = 24 ]]; then
    test "$(wc -c <"$TMP/$kind-$label.actual.sens")" -eq 5
    widened=$((widened+1))
  fi
  if [[ -n "$ORACLE" ]]; then
    if [[ "$kind" = add ]]; then
      printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$kind-$label.lisp"
    else
      printf '(помножити %s %s)\n' "$left" "$right" >"$TMP/$kind-$label.lisp"
    fi
    timeout 60s "$ORACLE" "$TMP/$kind-$label.lisp" \
      >"$TMP/$kind-$label.oracle.out" 2>"$TMP/$kind-$label.oracle.err"
    test ! -s "$TMP/$kind-$label.oracle.err"
    printf '%s\n' "$value" >"$TMP/$kind-$label.oracle.wanted"
    cmp "$TMP/$kind-$label.oracle.out" "$TMP/$kind-$label.oracle.wanted"
    oracle_count=$((oracle_count+1))
  fi
  success=$((success+1))
}
for row in \
  '01:0:0:0' '02:31:42:73' '03:-12:7:-5' \
  '04:-1024:-1024:-2048' '05:-2048:2047:-1' \
  '06:1023:1:1024' '07:2047:-2048:-1' \
  '08:2046:1:2047' '09:-2047:-1:-2048'; do
  IFS=: read -r label left right value <<<"$row"
  verify_case "$label" add "$TMP/add/$label.sens" \
    "$TMP/add/$label-expected.sens" "$left" "$right" "$value" 12
done
while IFS=$'\t' read -r label left right value width; do
  test -n "$label"
  verify_case "$label" mul "$TMP/mul/$label.sens" \
    "$TMP/mul/$label.expected.sens" "$left" "$right" "$value" "$width"
done <"$TMP/mul/cases.tsv"
test "$success" -eq 21
test "$widened" -eq 4
if [[ -n "$ORACLE" ]]; then test "$oracle_count" -eq 21;fi

# Не видаляємо і не послаблюємо старі негативи. Тільки D5:01010
# більше не є unsupported, тому other-d5 генерує pinned D5:01001.
neg=0
reject() {
  local label="$1";shift
  local dest="$TMP/rejected-$label.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$dest" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$dest" && test ! -L "$dest"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/reject.err"
  neg=$((neg+1))
}
for invalid in other-d5 other-d6 other-d7 bad-zero-arity \
  bad-zero-empty bad-zero-d1 bad-zero-d7 bad-less-arity \
  bad-less-d24 bad-less-d1 bad-greater-arity bad-greater-nested \
  bad-abs-arity bad-abs-d24 bad-abs-d3 \
  two-roots dotted unclosed root-atom bad-t5m empty; do
  reject "$invalid" "$FRONT" "$TMP/bad/$invalid.sens"
done
reject text "$FRONT" "$TMP/bad/fake.lisp"
reject missing "$FRONT" "$TMP/bad/absent.sens"
reject bad-mode --вигадано "$TMP/mul/01.sens"
test "$neg" -eq 24
cp "$TMP/add-01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/mul/02.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/add-01.elf"
ln -s "$TMP/no-file.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/mul/06.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/no-file.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/mul/06.sens" \
  "$TMP/recovered.elf" >"$TMP/recovered.out"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/mul/06.expected.sens"

# Довести чотири старі профілі та їхні 24 негативи ПОСЛІДОВНО.
timeout 600s bash scripts/test-irwidefront.sh >"$TMP/legacy.log" 2>"$TMP/legacy.err"
grep -Fq 'СПІЛЬНИЙ-WIDEIR-ГАРАЗД physical=16' "$TMP/legacy.log"
echo "ШІСТЬ-ПРОФІЛІВ-ГОТОВО add=9 mul=12 widened-D24=$widened machine=$success oracle=$oracle_count negative=$neg legacy=16 energy=NOT-MEASURED"
