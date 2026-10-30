#!/usr/bin/env bash
# G6.181 — фізичний pinned Core1 DEFINE/LAMBDA «частка» до reusable IDIV.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for tool in fpc timeout git cmp grep readelf python3 mktemp sha256sum; do
  command -v "$tool" >/dev/null || { echo "CORE1-ЧАСТКА-БЛОК: немає $tool" >&2;exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(визначити ядро1-частка' external/sens/lib/core1.lisp
grep -Fq '(10111 (ук частка) (укр частка)' external/sens/lib/domains/d5.lisp
ORACLE=${SENS_ORACLE_BIN:-}
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 ]];then test -n "$ORACLE";fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
finish(){
  local rc=$? f
  if ((rc));then
    echo "CORE1-ЧАСТКА-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for spec in \
  'scripts/test-elfd12quotpotik.pas test-elfd12quotpotik' \
  'src/senschyslo.lpr senschyslo' \
  'src/sensd12quotadaptive.lpr sensd12quotadaptive' \
  'src/senscore1chastkaadaptive.lpr senscore1chastkaadaptive'; do
  read -r src name <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd12quotpotik" "$TMP/physical" \
 >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'positive=25 numeric-reject=7 frame-reject=11' "$TMP/generator.log"

MODE=--зібрати-фізичну-core1-частку
ELF="$TMP/core1.elf"
timeout 90s "$TMP/bin/senscore1chastkaadaptive" "$MODE" "$ELF" \
 >"$TMP/core1.log" 2>"$TMP/core1.err"
test -x "$ELF"
grep -Fq 'CORE1-ЧАСТКА-ГОТОВО' "$TMP/core1.log"
if grep -Fq 'unfreed memory blocks' "$TMP/core1.err";then
  grep -Fq '0 unfreed memory blocks' "$TMP/core1.err"
else
  test ! -s "$TMP/core1.err"
fi
timeout 60s "$TMP/bin/sensd12quotadaptive" \
 --зібрати-адаптивну-D5-частку "$TMP/physical/anchor.sens" \
 "$TMP/d5.elf" >"$TMP/d5.log" 2>"$TMP/d5.err"
test -x "$TMP/d5.elf"
# Core1 exact D7 DEFINЕ повинен привести до ТОГО САМОГО emitter.
cmp "$ELF" "$TMP/d5.elf"
sha=$(sha256sum "$ELF" | cut -d' ' -f1)
readelf -h "$ELF" >"$TMP/header.log"
readelf -l "$ELF" >"$TMP/phdr.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/phdr.log"
python3 - "$ELF" <<'PY'
from pathlib import Path
import struct,sys
b=Path(sys.argv[1]).read_bytes()
assert b[:4]==b'\x7fELF'
assert struct.unpack_from('<Q',b,96)[0]==len(b)
assert struct.unpack_from('<Q',b,104)[0]==len(b)
assert b.count(bytes.fromhex('41 f7 f9'))==1, 'потрібен один x86 IDIV R9D'
print('CORE1-ЧАСТКА-МАШИНА-ПІДТВЕРДЖЕНО IDIV=1')
PY
PASS=0;ORACLE_PASS=0
while IFS=$'\t' read -r name a b expected;do
  test -n "$name"
  for attempt in 1 2;do
    timeout 7s "$ELF" <"$TMP/physical/$name.frame" \
      >"$TMP/$name-$attempt.actual.sens" 2>"$TMP/$name-$attempt.err"
    test ! -s "$TMP/$name-$attempt.err"
    cmp "$TMP/physical/$name.expected.sens" "$TMP/$name-$attempt.actual.sens"
    test "$(wc -c <"$TMP/$name-$attempt.actual.sens")" -eq 3
  done
  if [[ -n "$ORACLE" ]];then
    timeout 60s "$ORACLE" "$TMP/physical/$name.sens" \
      >"$TMP/$name.oracle" 2>"$TMP/$name.oracle.err"
    test ! -s "$TMP/$name.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$name.wanted"
    cmp "$TMP/$name.wanted" "$TMP/$name.oracle"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 25
printf '2048\n' >"$TMP/2048.lisp"
timeout 15s "$TMP/bin/senschyslo" --з-укр D24 \
  "$TMP/2048.lisp" "$TMP/promotion.expected.sens" >"$TMP/encode.log" 2>"$TMP/encode.err"
test "$(wc -c <"$TMP/promotion.expected.sens")" -eq 5
for attempt in 1 2;do
  timeout 7s "$ELF" <"$TMP/physical/promotion.frame" \
    >"$TMP/promotion-$attempt.sens" 2>"$TMP/promotion-$attempt.err"
  test ! -s "$TMP/promotion-$attempt.err"
  cmp "$TMP/promotion.expected.sens" "$TMP/promotion-$attempt.sens"
done
if [[ -n "$ORACLE" ]];then
  timeout 60s "$ORACLE" "$TMP/physical/promotion.sens" \
    >"$TMP/promotion.oracle" 2>"$TMP/promotion.oracle.err"
  cmp "$TMP/2048.lisp" "$TMP/promotion.oracle"
  ORACLE_PASS=$((ORACLE_PASS+1))
fi
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 26;fi

NEG=0
reject(){
  local file="$1" rc=0
  timeout 7s "$ELF" <"$file" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
  grep -Fq 'ВІДМОВА' "$TMP/reject.err"
  NEG=$((NEG+1))
}
while IFS=$'\t' read -r name a b;do
  [[ "$name" == promotion ]] && continue
  reject "$TMP/physical/$name.frame"
done <"$TMP/physical/numeric-reject.tsv"
for name in empty short1 short5 extra newline invalid243 badfirst \
            badsecond badlast projection d1;do
  reject "$TMP/physical/$name.frame"
done
test "$NEG" -eq 17
# Atomic no-clobber for existing target and dangling symlink.
rc=0
timeout 90s "$TMP/bin/senscore1chastkaadaptive" "$MODE" "$ELF" \
  >"$TMP/overwrite.out" 2>"$TMP/overwrite.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/overwrite.out"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$sha"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
rc=0
timeout 90s "$TMP/bin/senscore1chastkaadaptive" "$MODE" \
  "$TMP/dangling.elf" >"$TMP/link.out" 2>"$TMP/link.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/missing.elf"
# Fail closed when pinned tree is missing; no output is published.
rc=0
(cd "$TMP"; timeout 30s "$TMP/bin/senscore1chastkaadaptive" "$MODE" \
 "$TMP/absent.elf" >"$TMP/missing.out" 2>"$TMP/missing.err") || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/absent.elf" && test ! -s "$TMP/missing.out"
timeout 90s "$TMP/bin/senscore1chastkaadaptive" "$MODE" \
  "$TMP/recovered.elf" >"$TMP/recovered.log" 2>"$TMP/recovered.err"
cmp "$ELF" "$TMP/recovered.elf"
echo "G6.181-CORE1-ЧАСТКА-ГОТОВО core1=physical wideir=verified machine=IDIV d12=$PASS d24=1 oracle=$ORACLE_PASS negatives=$NEG no-clobber=2 recovered=так energy=NOT_MEASURED"
# 1) Чому після компіляції два D12 runtime-атоми можна змінювати?
# 2) Чому Core1 DEFINE мусить проходити точний D7-порядок параметрів?
# 3) Чому IDIV не може замінити SENS oracle?
# 4) Чому значення 2048 має фізичну ширину D24?
# 5) Чому stdout не містить UTF-8 проєкції результату?
