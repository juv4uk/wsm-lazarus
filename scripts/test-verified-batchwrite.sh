#!/usr/bin/env bash
# G6.230 — виконувані Linux write-guard для кожного D1 кореня.
# Canonical packed .sens/T5M, закони D1 та D2 — тільки pinned SENS.
# Один FPC PR runner через наявний verified-all, без Rust/Zig.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D1-ПАКЕТ-WRITE-БЛОК: Linux x86_64 потрібен' >&2; exit 127;
}
for tool in timeout fpc readelf objdump cmp mktemp; do
  command -v "$tool" >/dev/null || {
    echo "D1-ПАКЕТ-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Ця перевірка вже містить 1024 фізичні D1, native differential,
# malformed T5M/D2, no-clobber та побайтовий deterministic ELF.
if ! timeout 240s bash scripts/test-elfbatch.sh >"$TMP/original.log" 2>&1; then
  tail -n 70 "$TMP/original.log" >&2
  exit 1
fi
grep -Fq 'НАТИВНИЙ-ELF-ПАКЕТ-ВИКОНАННЯ-ГАРАЗД' "$TMP/original.log"

PASS=0
CLOSED=0
FULL=0
RECOVERY=0
for label in alternating separated maximum; do
  ELF="$ROOT/build/m0.2/elfbatch/$label.expected.elf"
  EXPECT="$ROOT/build/m0.2/elfbatch/$label.expected.out"
  test -s "$ELF" && test -s "$EXPECT"
  chmod 700 "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/header"
  grep -Eq 'Type:.*EXEC' "$TMP/header"
  tail -c +121 "$ELF" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/disasm"
  grep -Eq 'cmp[[:space:]]+rax,0x2' "$TMP/disasm"
  grep -Eq 'jne[[:space:]]' "$TMP/disasm"

  timeout 5s "$ELF" >"$TMP/out" 2>"$TMP/err"
  cmp "$EXPECT" "$TMP/out"
  test ! -s "$TMP/err"
  PASS=$((PASS+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" 2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.out" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.out"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 3 && test "$CLOSED" -eq 3 &&
  test "$FULL" -eq 3 && test "$RECOVERY" -eq 3
echo 'D1-BATCH-WRITE-PASS fpc=checked profiles=3 roots=3,4,1024 machine=CMP-RAX/JNE positives=3 closed=3 full=3 recovery=3 oracle=EXISTING-NATIVE energy=NOT-MEASURED'
