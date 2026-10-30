#!/usr/bin/env bash
# G6.234 — справжній D5:10011 ELF64 повинен повідомляти про невдалий Linux write.
# Тільки host ABI й машина; семантичний оракул для D5 — окремий pinned SENS REPL.
# Агрегатор verified запускає цей незалежний FPC+ELF свідок без нового workflow.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-ТРЕТЄ-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout git cmp grep readelf objdump mktemp tail; do
  command -v "$tool" >/dev/null || {
    echo "Д5-ТРЕТЄ-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "Д5-ТРЕТЄ-WRITE-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      if [[ -s "$f" ]]; then
        echo "--- $f" >&2
        tail -n 30 "$f" >&2
      fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-ird5third \
  "$ROOT/scripts/test-ird5third.pas" >"$TMP/fpc.log" 2>&1 || {
  cat "$TMP/fpc.log" >&2; exit 1;
}
test -x "$TMP/bin/test-ird5third"
HEAPTRC="log=$TMP/heap.log" timeout 90s \
  "$TMP/bin/test-ird5third" "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'D5-ТРЕТЄ-FPC-ГАРАЗД ELF=8 негативи=13' "$TMP/generator.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
# Точний новий 11-байтовий машинний епілог — лише host syscall ABI.
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' >"$TMP/checked-exit.bin"
PASS=0
CLOSED=0
FULL=0
RECOVERY=0
for i in {0..7}; do
  ELF="$TMP/physical/d5-$i.elf"
  EXPECT="$TMP/physical/d5-$i.expected.sens"
  test -s "$ELF" && test -s "$EXPECT"
  # 199 байтів початкового ELF + 11 байтів guarded host-епілога.
  test "$(wc -c <"$ELF")" -eq 210
  tail -c 11 "$ELF" | cmp - "$TMP/checked-exit.bin"
  timeout 5s readelf -h "$ELF" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$ELF" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$ELF" >"$TMP/code.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code.bin" >"$TMP/asm.log"
  grep -Fq '[rsi+0x10]' "$TMP/asm.log"
  grep -Fq 'setne' "$TMP/asm.log"
  chmod 700 "$ELF"
  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/actual.err"
  cmp "$EXPECT" "$TMP/actual.sens"
  test ! -s "$TMP/actual.err"
  PASS=$((PASS+1))

  # У Linux sys_write повертає -EBADF; процес не має брехати exit(0).
  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  # /dev/full дає -ENOSPC, не SENS D1:0 і не успішний запис.
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  # Наступне виконання того ж самого ELF має знову повертати точний D1.
  timeout 5s "$ELF" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.sens"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 8 && test "$CLOSED" -eq 8 &&
  test "$FULL" -eq 8 && test "$RECOVERY" -eq 8
echo 'Д5-ТРЕТЄ-WRITE-PASS fpc=checked elf=8 admission-negatives=13 closed=8 full=8 recovery=8 selector=UNCHANGED oracle=NOT-RUN energy=NOT-MEASURED'
