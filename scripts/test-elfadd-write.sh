#!/usr/bin/env bash
# G6.210: FPC -> реальні ET_DYN ELF64 і негатив закритого stdout.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЕЛФ-ДОДАВАННЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in fpc readelf objdump timeout cmp mktemp dd; do
  command -v "$exe" >/dev/null || { echo "ЕЛФ-ДОДАВАННЯ-БЛОК: немає $exe" >&2; exit 127; }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfadd-write "$ROOT/scripts/test-elfadd-write.pas"
timeout 30s "$TMP/bin/test-elfadd-write" "$TMP"
SUCCESS=0
NEGATIVE=0
for n in 0 1 2 3; do
  elf="$TMP/$n.elf"
  chmod 700 "$elf"
  readelf -h "$elf" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)'
  # У машинному потоці наявні ADD, CMP RAX,3 і JNE.
  # Наш ET_DYN не має section headers: дизасемблюємо RX PT_LOAD після 120-байтового ELF заголовка.
  dd if="$elf" of="$TMP/$n.machine" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$n.machine" >"$TMP/$n.asm"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$n.asm"
  grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/$n.asm"
  grep -Eiq '(^|[[:space:]])jne[[:space:]]' "$TMP/$n.asm"

  timeout 5s "$elf" >"$TMP/$n.actual.sens" 2>"$TMP/$n.err"
  test ! -s "$TMP/$n.err"
  test "$(wc -c <"$TMP/$n.actual.sens")" -eq 3
  cmp "$TMP/$n.actual.sens" "$TMP/$n.expected.sens"
  SUCCESS=$((SUCCESS+1))

  # Linux sys_write(1,rsp,3) поверне -EBADF, відтак саме ELF
  # зобов'язаний виконати exit(2), а не приховати помилку exit(0).
  code=0
  timeout 5s "$elf" 1>&- 2>"$TMP/$n.closed.err" || code=$?
  test "$code" -eq 2 || {
    echo "ЕЛФ-ДОДАВАННЯ-ЗБІЙ: fd1 закритий, exit=$code замість 2" >&2; exit 1;
  }
  test ! -s "$TMP/$n.closed.err"
  NEGATIVE=$((NEGATIVE+1))
  # Після негативу інший справжній процес усе ще повертає exact T5M.
  timeout 5s "$elf" >"$TMP/$n.recovery.sens" 2>"$TMP/$n.recovery.err"
  test ! -s "$TMP/$n.recovery.err"
  cmp "$TMP/$n.recovery.sens" "$TMP/$n.expected.sens"
done
echo "ЕЛФ-ДОДАВАННЯ-PASS native=$SUCCESS closed_stdout=$NEGATIVE recovery=4 D12=4 energy=НЕ-ВИМІРЯНО"
