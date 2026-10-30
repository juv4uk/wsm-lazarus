#!/usr/bin/env bash
# G6.236 — real x86-64 CMOV/D3 фізичні результати та Linux stdout.
# Тільки host-механіка; закони D1/D3, pinned D7 і T5M не змінюються.
# Запускається вже чинним test-verified-all.sh у fpc-headless.
# Вхід: pinned фізичні свідки через наявний FPC генератор.
# Вихід: машинний ELF64; тимчасові файли належать TMP і видаляються.
# 1) Чому EAX після sys_write не є мовним результатом D1?
# 2) Чому закритий fd1 означає невдачу навіть після правильного CMOV?
# 3) Чому перевіряємо всі 26 фізичних позитивів?
# 4) Чому D3:000 лишається відмінним від D1:0 у цьому тесті?
# 5) Який тест перевіряє незалежну семантику SENS? (Окремий oracle.)
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D3-CMOV-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in fpc timeout git cmp grep mktemp readelf tail chmod; do
  command -v "$tool" >/dev/null || {
    echo "D3-CMOV-WRITE-БЛОК: немає $tool" >&2
    exit 127
  }
done
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  2c498b35af53c085450eac6f51b87facf7f9aa47

TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "D3-CMOV-WRITE-ПРОВАЛ exit=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-ircondcmov \
  "$ROOT/scripts/test-ircondcmov.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2
    exit 1
  }
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-ircondcmov" \
  "$TMP/physical" >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2
    exit 1
  }
grep -Fq 'D3-CMOV-OK positives=26 negatives=16 PIE=26 T5M=26 first-true=1 recovery=1 energy=NOT-MEASURED' \
  "$TMP/fixtures.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test ! -s "$TMP/fixtures.err"

# Точні x86-64 байти: cmp eax,edx; setne dil; push 60; pop rax; syscall.
# EDX=1 — бажана кількість фізичних stdout байтів; RDI стає host 0/1.
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' \
  >"$TMP/epilogue.bin"

P=0; CLOSED=0; FULL=0; RECOVERY=0
for elf in "$TMP/physical/"*.elf; do
  [[ -f "$elf" ]] || { echo 'D3-CMOV-WRITE-БЛОК: немає ELF64' >&2; exit 1; }
  name="$(basename "$elf" .elf)"
  expected="$TMP/physical/$name.expected.sens"
  source="$TMP/physical/$name.sens"
  test -s "$source" && test -s "$expected" && test -s "$elf"
  chmod 700 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  tail -c 11 "$elf" | cmp - "$TMP/epilogue.bin"

  timeout 5s "$elf" >"$TMP/normal.out" 2>"$TMP/normal.err"
  test ! -s "$TMP/normal.err"
  cmp "$expected" "$TMP/normal.out"
  P=$((P+1))

  # Реальне ядро Linux: -EBADF при закритому stdout, host exit(1).
  code=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$elf" \
    2>"$TMP/closed.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  # Реальне ядро Linux: /dev/full -> -ENOSPC, host exit(1).
  code=0
  timeout 5s "$elf" >/dev/full 2>"$TMP/full.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$elf" >"$TMP/recovery.out" 2>"$TMP/recovery.err"
  cmp "$expected" "$TMP/recovery.out"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done

test "$P" -eq 26 && test "$CLOSED" -eq 26 &&
  test "$FULL" -eq 26 && test "$RECOVERY" -eq 26
echo 'D3-CMOV-WRITE-PASS FPC=checked physical=26 ELF=26 pinned-negatives=16 host-closed=26 host-full=26 recovery=26 independent-oracle=EXISTING-SEPARATE energy=NOT-MEASURED'
