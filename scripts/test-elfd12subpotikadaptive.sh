#!/usr/bin/env bash
# G6.174 — один фізичний D5:01011 → повторно виконуваний x86-64 SUB.
# Закон віднімання тільки з pinned SENS; host-тест звіряє фізичні байти.
# Input .sens — borrowed файл, дві W12 frame — власні тимчасові байти;
# output 3/5 T5M байтів перевірено; TMP і виходи живуть до EXIT trap.
# Питання:
#  1) Чому SUB мусить приймати різні runtime W12 без нової компіляції?
#  2) Чому 5 фізичних байтів D24 відрізняються від W12?
#  3) Чому порожній або заширокий stdin має бути відхилений?
#  4) Чому незалежний SENS oracle не можна замінити host arithmetic?
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc timeout git readelf cmp python3 mktemp sha256sum grep wc; do
  command -v "$exe" >/dev/null || { echo "АДАПТИВНЕ-SUB-БЛОК: немає $exe" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01011 (ук відняти) (укр відняти)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo "АДАПТИВНЕ-SUB-БЛОК: немає незалежного SENS oracle" >&2; exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "АДАПТИВНЕ-SUB-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 25 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units-sub" "$TMP/units-cli" "$TMP/units-num" "$TMP/inputs"
for row in \
  'scripts/test-irwidesub.pas test-irwidesub units-sub' \
  'src/sensd12addpotikadaptive.lpr sensd12addpotikadaptive units-cli' \
  'src/senschyslo.lpr senschyslo units-num'; do
  read -r source name units <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidesub" "$TMP/inputs" \
  >"$TMP/cases.log" 2>"$TMP/cases.err"
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/cases.log"
test "$(wc -l <"$TMP/inputs/cases.tsv")" -eq 12
ELF="$TMP/видати-віднімання.elf"
MODE=--зібрати-адаптивне-D5-віднімання
timeout 45s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/inputs/01.sens" "$ELF" >"$TMP/compiler.out" 2>"$TMP/compiler.err"
grep -Fq 'АДАПТИВНЕ-D5-SUB-ГОТОВО' "$TMP/compiler.out"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/elf.h"
readelf -l "$ELF" >"$TMP/elf.l"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.h"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.h"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/elf.l"
python3 - "$ELF" <<'PY'
import struct, sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
assert b[:4] == b'\x7fELF'
assert struct.unpack_from('<Q', b, 96)[0] == len(b)
assert struct.unpack_from('<Q', b, 104)[0] == len(b)
assert b'\x44\x89\xc0\x44\x29\xc8\x89\xc3' in b, 'немає нативного SUB'
assert b'\x48\x83\xf8\x05\x0f\x85' in b, 'немає перевірки write(5)'
PY
timeout 45s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/inputs/04.sens" "$TMP/rebuilt.elf" >"$TMP/rebuilt.out"
cmp "$ELF" "$TMP/rebuilt.elf"
sha256sum "$ELF" >"$TMP/original.sha"
small=0; wide=0; oracles=0; machine=0
while IFS=$'\t' read -r label left right wanted width; do
  test -n "$label" && test -n "$left" && test -n "$right"
  test "$width" = 12 || test "$width" = 24
  printf '%s\n' "$left" >"$TMP/$label.left.lisp"
  printf '%s\n' "$right" >"$TMP/$label.right.lisp"
  timeout 12s "$TMP/bin/senschyslo" --з-укр D12 \
    "$TMP/$label.left.lisp" "$TMP/$label.left.sens" >"$TMP/$label.mint1"
  timeout 12s "$TMP/bin/senschyslo" --з-укр D12 \
    "$TMP/$label.right.lisp" "$TMP/$label.right.sens" >"$TMP/$label.mint2"
  cat "$TMP/$label.left.sens" "$TMP/$label.right.sens" >"$TMP/$label.frame"
  test "$(wc -c <"$TMP/$label.frame")" -eq 6
  for attempt in 1 2; do
    timeout 6s "$ELF" <"$TMP/$label.frame" \
      >"$TMP/$label.$attempt.actual.sens" 2>"$TMP/$label.$attempt.err"
    test ! -s "$TMP/$label.$attempt.err"
    cmp "$TMP/inputs/$label.expected.sens" "$TMP/$label.$attempt.actual.sens"
    if [[ "$width" == 12 ]]; then
      test "$(wc -c <"$TMP/$label.$attempt.actual.sens")" -eq 3
    else
      test "$(wc -c <"$TMP/$label.$attempt.actual.sens")" -eq 5
    fi
    machine=$((machine+1))
  done
  if [[ "$width" == 12 ]]; then small=$((small+1)); else wide=$((wide+1)); fi
  if [[ -n "$ORACLE" ]]; then
    printf '(відняти %s %s)\n' "$left" "$right" >"$TMP/$label.oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    timeout 12s "$TMP/bin/senschyslo" --в-укр D"$width" \
      "$TMP/$label.1.actual.sens" >"$TMP/$label.ukr"
    cmp "$TMP/$label.oracle" "$TMP/$label.ukr"
    oracles=$((oracles+1))
  fi
done <"$TMP/inputs/cases.tsv"
test "$small" -eq 8 && test "$wide" -eq 4 && test "$machine" -eq 24
if [[ -n "$ORACLE" ]]; then test "$oracles" -eq 12; fi
neg=0
reject_stdin() {
  local label="$1" input="$2" rc=0
  timeout 6s "$ELF" <"$input" >"$TMP/$label.out" 2>"$TMP/$label.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.out"
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/$label.err"
  neg=$((neg+1))
}
: >"$TMP/empty.frame"
head -c 5 "$TMP/01.frame" >"$TMP/short.frame"
cp "$TMP/01.frame" "$TMP/extra.frame"
printf '\000' >>"$TMP/extra.frame"
printf '\377\377\377\377\377\377' >"$TMP/invalid.frame"
printf '123456\n' >"$TMP/projection.frame"
for kind in empty short extra invalid projection; do
  reject_stdin "$kind" "$TMP/$kind.frame"
done
test "$neg" -eq 5
anchor_neg=0
reject_anchor() {
  local label="$1" source="$2" rc=0
  timeout 45s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
    "$source" "$TMP/reject-$label.elf" \
    >"$TMP/anchor-$label.out" 2>"$TMP/anchor-$label.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/anchor-$label.out"
  test ! -e "$TMP/reject-$label.elf"
  grep -Fq 'АДАПТИВНЕ-D5-SUB-ВІДМОВА:' "$TMP/anchor-$label.err"
  anchor_neg=$((anchor_neg+1))
}
printf '\377' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
cp "$TMP/inputs/01.sens" "$TMP/projection.lisp"
head -c 2 "$TMP/inputs/01.sens" >"$TMP/truncated.sens"
for kind in corrupt.sens empty.sens projection.lisp truncated.sens; do
  reject_anchor "$anchor_neg" "$TMP/$kind"
done
test "$anchor_neg" -eq 4
rc=0
timeout 45s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/inputs/01.sens" "$ELF" >"$TMP/noclobber.out" \
  2>"$TMP/noclobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/noclobber.out"
sha256sum -c "$TMP/original.sha"
timeout 45s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/inputs/01.sens" "$TMP/recovered.elf" >"$TMP/recovered.out"
cmp "$ELF" "$TMP/recovered.elf"
echo "АДАПТИВНЕ-SUB-ГОТОВО d12=$small d24=$wide machine=$machine oracle=$oracles negative-stdin=$neg negative-anchor=$anchor_neg no-clobber=yes energy=NOT-MEASURED"
