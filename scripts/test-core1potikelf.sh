#!/usr/bin/env bash
# G6.161 — pinned фізичний Core1 → один ELF для ДЕСЯТКІВ runtime D12.
# Семантика тільки в external/sens. Machine D12->D24 overflow fail-closed.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git fpc timeout cmp sha256sum readelf objdump grep mktemp; do
  command -v "$tool" >/dev/null || { echo "ЯДРО1-ПОТІК-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "ЯДРО1-ПОТІК-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 60s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test -s external/sens/lib/core1.sens
grep -Fq '(визначити ядро1-додати' external/sens/lib/core1.lisp
grep -Fq '(визначити ядро1-відняти' external/sens/lib/core1.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'ЯДРО1-ПОТІК-БЛОК: незалежний pinned SENS REPL обовʼязковий' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if (( rc )); then
    echo "ЯДРО1-ПОТІК-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixtures" "$TMP/data"
for spec in \
 'src/senscore1potikelf.lpr senscore1potikelf units-cli' \
 'scripts/test-core1potik-fixtures.pas test-core1potik-fixtures units-fixtures' \
 'src/senswideaddpotik.lpr senswideaddpotik units-cli'; do
  read -r source binary units <<< "$spec"
  timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>&1 || {
      cat "$TMP/$binary.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 40s "$TMP/bin/test-core1potik-fixtures" "$TMP/data" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'CORE1-POTIK-FIXTURES-OK total=40 d12=33 d24=7 bad=7' "$TMP/fixtures.out"
test ! -s "$TMP/fixtures.err"
test "$(wc -l <"$TMP/data/cases.tsv")" -eq 33
test "$(wc -l <"$TMP/data/promotion.tsv")" -eq 7
MODE_ADD=--ядро1-додати-потік
MODE_SUB=--ядро1-відняти-потік
for op in a s; do
  if [[ "$op" == a ]]; then mode="$MODE_ADD"; else mode="$MODE_SUB"; fi
  timeout 90s "$TMP/bin/senscore1potikelf" "$mode" "$TMP/$op.elf" \
    >"$TMP/$op.compile.out" 2>"$TMP/$op.compile.err"
  test -x "$TMP/$op.elf"
  grep -Fq 'ЯДРО1-ПОТІК-ELF-ГОТОВО' "$TMP/$op.compile.out"
  ! grep -Eq 'unfreed memory blocks' "$TMP/$op.compile.err" ||
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/$op.compile.err"
  readelf -h "$TMP/$op.elf" >"$TMP/$op.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$op.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$op.header"
  ! readelf -l "$TMP/$op.elf" | grep -Eq 'INTERP|DYNAMIC'
  dd if="$TMP/$op.elf" of="$TMP/$op.code" bs=1 skip=120 count=500 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$op.code" >"$TMP/$op.asm"
  if [[ "$op" == a ]]; then
    grep -Eiq 'add[[:space:]]+eax,r9d' "$TMP/$op.asm"
  else
    grep -Eiq 'sub[[:space:]]+eax,r9d' "$TMP/$op.asm"
  fi
done
# ADD Core1 machine має той самий результат, що pinned WideIR dynamic ADD,
# але source admission пройшов оригінальний бібліотечний DEFINE.
timeout 50s "$TMP/bin/senswideaddpotik" \
  --зібрати-D5-додавання-потік "$TMP/data/a00.sens" "$TMP/donor.elf" \
  >"$TMP/donor.out" 2>"$TMP/donor.err"
cmp "$TMP/a.elf" "$TMP/donor.elf"
HASH_A=$(sha256sum "$TMP/a.elf" | cut -d' ' -f1)
HASH_S=$(sha256sum "$TMP/s.elf" | cut -d' ' -f1)
PASS=0;ORACLE_PASS=0
while IFS=$'\t' read -r label head a b expected width; do
  test "$width" = 12
  op="${label:0:1}"
  test "$op" = a || test "$op" = s
  for cycle in 1 2; do
    timeout 5s "$TMP/$op.elf" <"$TMP/data/$label.frame" \
      >"$TMP/$label.$cycle.actual.sens" 2>"$TMP/$label.$cycle.err"
    test ! -s "$TMP/$label.$cycle.err"
    cmp "$TMP/data/$label.expected.sens" "$TMP/$label.$cycle.actual.sens"
    test "$(wc -c <"$TMP/$label.$cycle.actual.sens")" -eq 3
  done
  cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
  if [[ -n "$ORACLE" ]]; then
    if [[ "$op" == a ]]; then call=додати; else call=відняти; fi
    printf '(%s %s %s)\n' "$call" "$a" "$b" >"$TMP/$label.oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle.out"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/data/cases.tsv"
test "$PASS" -eq 33
test "$(sha256sum "$TMP/a.elf" | cut -d' ' -f1)" = "$HASH_A"
test "$(sha256sum "$TMP/s.elf" | cut -d' ' -f1)" = "$HASH_S"
PROMOTED=0
while IFS=$'\t' read -r label head a b expected width; do
  test "$width" = 24
  op="${label:0:1}"
  rc=0
  timeout 5s "$TMP/$op.elf" <"$TMP/data/$label.frame" \
    >"$TMP/$label.overflow.out" 2>"$TMP/$label.overflow.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.overflow.out"
  grep -Fq 'ВІДМОВА' "$TMP/$label.overflow.err"
  test "$(wc -c <"$TMP/data/$label.expected.sens")" -eq 5
  if [[ -n "$ORACLE" ]]; then
    if [[ "$op" == a ]]; then call=додати; else call=відняти; fi
    printf '(%s %s %s)\n' "$call" "$a" "$b" >"$TMP/$label.oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle.out"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PROMOTED=$((PROMOTED+1))
done <"$TMP/data/promotion.tsv"
test "$PROMOTED" -eq 7
BAD=0
for op in a s; do
  for name in empty short extra bad-first bad-middle text d1; do
    rc=0
    timeout 5s "$TMP/$op.elf" <"$TMP/data/$name.frame" \
      >"$TMP/bad.out" 2>"$TMP/bad.err" || rc=$?
    test "$rc" -eq 2 && test ! -s "$TMP/bad.out"
    grep -Fq 'ВІДМОВА' "$TMP/bad.err"
    BAD=$((BAD+1))
  done
done
test "$BAD" -eq 14
# No-clobber навіть через dangling symlink, без видалення target.
cp "$TMP/a.elf" "$TMP/occupied.elf"
rc=0
timeout 40s "$TMP/bin/senscore1potikelf" "$MODE_SUB" "$TMP/occupied.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/a.elf" "$TMP/occupied.elf"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
rc=0
timeout 40s "$TMP/bin/senscore1potikelf" "$MODE_ADD" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/missing.elf"
timeout 5s "$TMP/a.elf" <"$TMP/data/a01.frame" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/data/a01.expected.sens"
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 40; fi
echo "ЯДРО1-ПОТІК-ГОТОВО physical-core1=2 kernels=2 d12=$PASS native=$((2*PASS)) d24-rejected=$PROMOTED bad-frames=$BAD oracle=$ORACLE_PASS no-clobber=2 recovery=1 energy=NOT-MEASURED"
