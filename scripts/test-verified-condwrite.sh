#!/usr/bin/env bash
# G6.226 — host Linux write(1,rsp,2|3) та recovery для D3:110.
# Лише машинний stdout: SENS Contract12, D7 і D12+ не змінюємо.
# Один існуючий fpc-headless runner через test-verified-all.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'УМОВА-WRITE-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc readelf objdump cmp mktemp; do
  command -v "$tool" >/dev/null || {
    echo "УМОВА-WRITE-БЛОК: бракує $tool" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Чинний тест сам будує source з фізичного T5M та генерує 32
# незалежно виконувані ELF, порівнює їх з native D3 executor і має
# збережені admission-негативи. Не замінюємо його grep-імітацією.
if ! timeout 240s bash scripts/test-elfcond.sh >"$TMP/base.log" 2>&1; then
  tail -n 65 "$TMP/base.log" >&2
  exit 1
fi
grep -Fq 'МАШИННА-УМОВА-ЕЛФ-ГАРАЗД' "$TMP/base.log"

PASS=0
CLOSED=0
FULL=0
RECOVERY=0
for name in без-гілок одна-істинна одна-хибна вираз-рівність-01 тридцять-дві-вичерпано; do
  ELF="$TMP/$name.elf"
  EXPECT="$ROOT/build/m0.2/elfcond/$name.expected.out"
  cp "$ROOT/build/m0.2/elfcond/$name.expected.elf" "$ELF"
  chmod 700 "$ELF"
  test -s "$ELF" && test -s "$EXPECT"
  timeout 5s readelf -h "$ELF" >"$TMP/header"
  grep -Eq 'Type:.*EXEC' "$TMP/header"
  # Відділяємо 120 байтів ELF header/phdr від x86-64 machine.
  tail -c +121 "$ELF" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/disasm"
  grep -Eq 'cmp[[:space:]]+rax,0x[23]' "$TMP/disasm"
  grep -Eq 'jne[[:space:]]' "$TMP/disasm"
  grep -Fq 'syscall' "$TMP/disasm"

  timeout 5s "$ELF" >"$TMP/normal.out" 2>"$TMP/normal.err"
  cmp "$EXPECT" "$TMP/normal.out"
  test ! -s "$TMP/normal.err"
  PASS=$((PASS+1))

  RC=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" 2>"$TMP/closed.err" || RC=$?
  test "$RC" -eq 2 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  RC=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || RC=$?
  test "$RC" -eq 2 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.out" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.out"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 5 && test "$CLOSED" -eq 5 &&
  test "$FULL" -eq 5 && test "$RECOVERY" -eq 5
echo 'D3-COND-WRITE-PASS fpc=checked elf=5 original-elf=32 closed=5 full=5 recovery=5 host=RAX-CMP/JNE pinned-admission=EXISTING oracle=EXISTING-NATIVE energy=NOT-MEASURED'
