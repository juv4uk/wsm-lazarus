#!/usr/bin/env bash
# G6.231 — виконуваний ET_EXEC для D3:100/011; жодного нового D3 закону.
# Реальний FPC перевіряє donor, захищену публікацію та 8 machine ELF.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'СЕЛЕКТОР-ASCII-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp mktemp tail; do
  command -v "$tool" >/dev/null || {
    echo "СЕЛЕКТОР-ASCII-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Повний 8×machine ELF і 14 admission відмов уже виконуються базовим
# тестом. Похідний T5M donor НЕ змінено: окремий verified gate зберігається.
if ! timeout 240s bash scripts/test-elfselector.sh >"$TMP/baseline.log" 2>&1; then
  tail -n 75 "$TMP/baseline.log" >&2
  exit 1
fi
grep -Fq 'МАШИННИЙ-ВИБІР-ELF-ГАРАЗД' "$TMP/baseline.log"
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' >"$TMP/checked.bin"

PASS=0
CLOSED=0
FULL=0
RECOVERY=0
for label in перше-00 перше-01 перше-10 перше-11 \
  решта-00 решта-01 решта-10 решта-11; do
  ELF="$ROOT/build/m0.2/elfselector/$label.expected.elf"
  EXPECT="$ROOT/build/m0.2/elfselector/$label.expected.out"
  test -s "$ELF" && test -s "$EXPECT"
  test "$(wc -c <"$ELF")" -eq 206
  chmod 700 "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/hdr"
  grep -Eq 'Type:.*EXEC' "$TMP/hdr"
  tail -c 11 "$ELF" | cmp - "$TMP/checked.bin"
  tail -c +121 "$ELF" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm"
  grep -Fq 'setne' "$TMP/asm"
  grep -Fq 'syscall' "$TMP/asm"

  timeout 5s "$ELF" >"$TMP/actual.out" 2>"$TMP/actual.err"
  cmp "$EXPECT" "$TMP/actual.out"
  test ! -s "$TMP/actual.err"
  PASS=$((PASS+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.out" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.out"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 8 && test "$CLOSED" -eq 8 && \
  test "$FULL" -eq 8 && test "$RECOVERY" -eq 8
echo 'D3-SELECTOR-ASCII-WRITE-PASS fpc=checked elf=8 admission-negatives=14 closed=8 full=8 recovery=8 donor=UNCHANGED native-parity=8 independent-SENS-oracle=NOT-RUN energy=NOT-MEASURED'
