#!/usr/bin/env bash
# G6.118 — СПІЛЬНИЙ фізичний compiler WideIR: 6 → 8 verified profiles.
# Ратифіковані голови: D5:01011 (відняти), D6:010101 (НСД).
# Ті самі packed T5M/D2 вхідні фізичні програми у спеціалізований
# компілятор та спільний фронтенд мають дати ПОБАЙТОВО той самий ELF.
# Обидва ELF реально виконуються; математику підтверджує pinned SENS.
# 1) Чому Width(5/6) і HasPinnedKey разом із Bits потрібні?
# 2) Чому D6:010101 не дозволяє нуль/від'ємний D12 у цьому профілі?
# 3) Хто забезпечує розширення D12 → D24 на відніманні?
# 4) Чому byte-identical ELF не підміняє перевірку oracle?
# 5) Чому всі host fixture/compiled artifacts живуть у mktemp?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ВІСІМ-ПРОФІЛІВ-БЛОК: потрібен Linux x86-64' >&2;exit 127; }
for binary in fpc git timeout readelf objdump cmp mktemp grep dd tail wc; do
  command -v "$binary" >/dev/null || {
    echo "ВІСІМ-ПРОФІЛІВ-БЛОК: бракує $binary" >&2; exit 127; }
done
timeout 120s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(01011 (ук відняти) (укр відняти)' external/sens/lib/domains/d5.lisp
grep -Fq '(010101 (ук нсд) (укр найбільший-спільний-дільник)' external/sens/lib/domains/d6.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc != 0)); then
    echo "ВІСІМ-ПРОФІЛІВ-ПОМИЛКА: exit=$rc" >&2
    for log in "$TMP"/*.build.log "$TMP"/*.err "$TMP"/*.oracle.err "$TMP"/*.regression.err; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 55 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap finish EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/sub" "$TMP/nsd"
for row in \
  'scripts/test-irwidesub.pas:test-irwidesub' \
  'scripts/test-irwidensd.pas:test-irwidensd' \
  'src/senswidefrontelf.lpr:senswidefrontelf' \
  'src/senswidesubelf.lpr:senswidesubelf' \
  'src/senswidensdelf.lpr:senswidensdelf'; do
  IFS=: read -r pas exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$pas" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2;exit 1; }
  test -x "$TMP/bin/$exe"
done
check_heap() {
  if [[ -s "$1" ]]; then
    grep -Fq '0 unfreed memory blocks' "$1" || {
      echo "ВИТІК У $1" >&2;cat "$1" >&2;return 1; }
  fi
}
HEAPTRC="log=$TMP/sub.heap" timeout 30s "$TMP/bin/test-irwidesub" "$TMP/sub" \
  >"$TMP/sub.fixtures.out" 2>"$TMP/sub.fixtures.err"
HEAPTRC="log=$TMP/nsd.heap" timeout 30s "$TMP/bin/test-irwidensd" "$TMP/nsd" \
  >"$TMP/nsd.fixtures.out" 2>"$TMP/nsd.fixtures.err"
check_heap "$TMP/sub.heap";check_heap "$TMP/nsd.heap"
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/sub.fixtures.out"
grep -Fq 'G6.105-NSD-FIXTURES-OK cases=14' "$TMP/nsd.fixtures.out"

FRONT=--скомпілювати-фізичну-форму
SUB=--скомпілювати-віднімання-Д5
NSD=--скомпілювати-D6-нсд-D12
pass=0;subpass=0;nsdpass=0;wide=0;oraclecount=0
proof() {
  local profile="$1" label="$2" left="$3" right="$4" wanted="$5" width="$6"
  local src="$TMP/$profile/$label.sens"
  local elf="$TMP/$profile-$label.elf" golden="$TMP/$profile-$label.gold.elf"
  HEAPTRC="log=$TMP/$profile-$label.heap" timeout 20s \
    "$TMP/bin/senswidefrontelf" "$FRONT" "$src" "$elf" \
    >"$TMP/$profile-$label.front.out" 2>"$TMP/$profile-$label.front.err"
  test -x "$elf"
  test ! -s "$TMP/$profile-$label.front.err"
  check_heap "$TMP/$profile-$label.heap"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$profile-$label.front.out"
  if [[ "$profile" == sub ]]; then
    timeout 20s "$TMP/bin/senswidesubelf" "$SUB" "$src" "$golden" \
      >"$TMP/$profile-$label.special.out" 2>"$TMP/$profile-$label.special.err"
  else
    timeout 20s "$TMP/bin/senswidensdelf" "$NSD" "$src" "$golden" \
      >"$TMP/$profile-$label.special.out" 2>"$TMP/$profile-$label.special.err"
  fi
  cmp "$elf" "$golden"
  readelf -h "$elf" >"$TMP/$profile-$label.header"
  grep -Eq 'Type:.*DYN' "$TMP/$profile-$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$profile-$label.header"
  readelf -l "$elf" >"$TMP/$profile-$label.phdr"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$profile-$label.phdr"
  dd if="$elf" of="$TMP/$profile-$label.code" bs=1 skip=120 count=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$profile-$label.code" >"$TMP/$profile-$label.asm"
  if [[ "$profile" == sub ]]; then
    grep -Eq 'sub[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$profile-$label.asm"
    subpass=$((subpass+1))
  else
    grep -Eq 'div[[:space:]]+ecx' "$TMP/$profile-$label.asm"
    grep -Eq 'jmp[[:space:]]' "$TMP/$profile-$label.asm"
    nsdpass=$((nsdpass+1))
  fi
  timeout 5s "$elf" >"$TMP/$profile-$label.actual.sens" \
    2>"$TMP/$profile-$label.exec.err"
  test ! -s "$TMP/$profile-$label.exec.err"
  cmp "$TMP/$profile-$label.actual.sens" "$TMP/$profile/$label.expected.sens"
  if [[ "$width" == 24 ]]; then
    test "$(wc -c <"$TMP/$profile-$label.actual.sens")" -eq 5
    wide=$((wide+1))
  else
    test "$width" = 12
    test "$(wc -c <"$TMP/$profile-$label.actual.sens")" -eq 3
  fi
  if [[ -n "$ORACLE" ]]; then
    if [[ "$profile" == sub ]]; then
      printf '(відняти %s %s)\n' "$left" "$right" >"$TMP/$profile-$label.lisp"
    else
      printf '(найбільший-спільний-дільник %s %s)\n' "$left" "$right" \
        >"$TMP/$profile-$label.lisp"
    fi
    timeout 60s "$ORACLE" "$TMP/$profile-$label.lisp" \
      >"$TMP/$profile-$label.oracle" 2>"$TMP/$profile-$label.oracle.err"
    test ! -s "$TMP/$profile-$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$profile-$label.wanted"
    cmp "$TMP/$profile-$label.oracle" "$TMP/$profile-$label.wanted"
    oraclecount=$((oraclecount+1))
  fi
  pass=$((pass+1))
}
while IFS=$'\t' read -r label left right expected width; do
  test -n "$label"
  proof sub "$label" "$left" "$right" "$expected" "$width"
done <"$TMP/sub/cases.tsv"
while IFS=$'\t' read -r label left right expected; do
  test -n "$label"
  proof nsd "$label" "$left" "$right" "$expected" 12
done <"$TMP/nsd/cases.tsv"
test "$pass" -eq 26
test "$subpass" -eq 12
test "$nsdpass" -eq 14
test "$wide" -eq 4
if [[ -n "$ORACLE" ]]; then test "$oraclecount" -eq 26;fi

# НЕ послаблювати жодної помилки. Поза 8 профілями — explicit fail closed.
negative=0
reject() {
  local label="$1";shift
  local target="$TMP/rejected-$negative.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "ВІСІМ-ПРОФІЛІВ-НЕГАТИВ: $label rc=$rc" >&2;return 1
  fi
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  negative=$((negative+1))
}
# Чужі pinned D5/D6 голови залишаються НЕПІДТРИМАНИМИ.
# Старий "other-d5" у профільному fixture є легальним ADD для front.
# Перевірку непідтриманої голови покриває legacy six-regression:
# pinned D5:01001 та pinned D6:010010, без вилучення негативів.
for invalid in other-d6 other-d7 d1 d3-empty d7 d24 missing extra nested \
  two-roots dotted root-atom unclosed close-only bad-t5m empty \
  zero-left zero-right negative-left negative-right; do
  reject "$invalid" "$FRONT" "$TMP/nsd/$invalid.sens"
done
reject missing-source "$FRONT" "$TMP/nsd/missing-source.sens"
reject projection "$FRONT" "$TMP/nsd/fake.lisp"
reject unknown-mode --непідтриманий "$TMP/nsd/01.sens"
test "$negative" -eq 23

# No-clobber / dangling symlink / recovery після відмови.
cp "$TMP/sub-01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/nsd/02.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/sub-01.elf"
ln -s "$TMP/forbidden.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/nsd/03.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2
test -L "$TMP/dangling.elf"
test ! -e "$TMP/forbidden.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/nsd/14.sens" \
  "$TMP/recovered.elf" >"$TMP/recovered.out"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/nsd/14.expected.sens"

# ПОВНА регресія 6 старих профілів, а не тільки тест компіляції units.
timeout 900s bash scripts/test-irwidefront-aryfmetyka.sh \
  >"$TMP/legacy.regression.out" 2>"$TMP/legacy.regression.err" || {
    tail -n 80 "$TMP/legacy.regression.err" >&2;exit 1; }
grep -Fq 'ШІСТЬ-ПРОФІЛІВ-ГОТОВО add=9 mul=12 widened-D24=4 machine=21' \
  "$TMP/legacy.regression.out"
echo "ВІСІМ-ПРОФІЛІВ-ГОТОВО: sub=$subpass nsd=$nsdpass total=$pass widened-D24=$wide oracle=$oraclecount negative=$negative legacy-six=yes energy=NOT-MEASURED"
