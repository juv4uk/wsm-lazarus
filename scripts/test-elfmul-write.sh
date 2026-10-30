#!/usr/bin/env bash
# G6.211: 8 справжніх x86-64 IMUL ELF; 3-byte D12 і 5-byte D24,
# машина відхиляє host-короткий або невдалий write.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЕЛФ-МНОЖЕННЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in fpc readelf objdump timeout cmp mktemp dd wc grep; do
  command -v "$exe" >/dev/null || {
    echo "ЕЛФ-МНОЖЕННЯ-БЛОК: немає $exe" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfmul-write "$ROOT/scripts/test-elfmul-write.pas"
timeout 30s "$TMP/bin/test-elfmul-write" "$TMP"
SUCCESS=0
CLOSED=0
RECOVERY=0
for i in 0 1 2 3 4 5 6 7; do
  elf="$TMP/$i.elf"
  chmod 700 "$elf"
  readelf -h "$elf" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)'
  if (( i<5 )); then width=12; count=3; else width=24; count=5; fi
  test "$(wc -c <"$TMP/$i.expected.sens")" -eq "$count"
  # Генератор ET_DYN не записує section headers: RX segment після 120B.
  dd if="$elf" of="$TMP/$i.machine" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$i.machine" >"$TMP/$i.asm"
  grep -Eiq 'imul[[:space:]]+eax,eax,' "$TMP/$i.asm"
  grep -Eiq "cmp[[:space:]]+rax,0x$count" "$TMP/$i.asm"
  grep -Eiq '(^|[[:space:]])jne[[:space:]]' "$TMP/$i.asm"

  timeout 5s "$elf" >"$TMP/$i.actual.sens" 2>"$TMP/$i.err"
  test ! -s "$TMP/$i.err"
  test "$(wc -c <"$TMP/$i.actual.sens")" -eq "$count"
  cmp "$TMP/$i.expected.sens" "$TMP/$i.actual.sens"
  SUCCESS=$((SUCCESS+1))

  # Закритий descriptor 1 -> -EBADF у machine write -> exit(2).
  exit_code=0
  timeout 5s "$elf" 1>&- 2>"$TMP/$i.closed.err" || exit_code=$?
  test "$exit_code" -eq 2 || {
    echo "ЕЛФ-МНОЖЕННЯ-ЗБІЙ: D$width fd1 закритий, exit=$exit_code" >&2
    exit 1
  }
  test ! -s "$TMP/$i.closed.err"
  CLOSED=$((CLOSED+1))

  timeout 5s "$elf" >"$TMP/$i.recovery.sens" 2>"$TMP/$i.recovery.err"
  test ! -s "$TMP/$i.recovery.err"
  cmp "$TMP/$i.expected.sens" "$TMP/$i.recovery.sens"
  RECOVERY=$((RECOVERY+1))
done
echo "ЕЛФ-МНОЖЕННЯ-PASS native=$SUCCESS closed_stdout=$CLOSED recovery=$RECOVERY D12=5 D24=3 malformed=reject energy=НЕ-ВИМІРЯНО"
