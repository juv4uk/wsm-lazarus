#!/usr/bin/env bash
# G6 — повторне використання перевіреного машинного write guard у двох
# D3:101 CALL/RET backend. Лише host Linux ABI, НЕ мовний закон SENS.
# Запускається чинним verified-all FPC job, без нового apt/Rust/Zig.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D3-CALL-ЗАПИС-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump git mktemp; do
  command -v "$tool" >/dev/null || {
    echo "D3-CALL-ЗАПИС-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 60s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  1f1bf676eeac605e065035d9dd2adaae807f1788
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-ircallwriter "$ROOT/scripts/test-ircallwriter.pas" \
  >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
timeout 50s "$TMP/bin/test-ircallwriter" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2; exit 1;
  }
grep -Fq 'G6_107_OK ELF=4 PHYS_NEG=13 HOST_NEG=12' "$TMP/fixtures.log"
# Postpass checked-exit: CMP EAX,EDX; SETNE DIL; PUSH 60; POP RAX; SYSCALL.
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' \
  >"$TMP/checked.bytes"
P=0; EBADF=0; ENOSPC=0; RECOVERY=0
for name in рівність-00 рівність-01 рівність-10 рівність-11; do
  ELF="$TMP/physical/$name.elf"
  EXPECT="$TMP/physical/$name.expected.sens"
  test -s "$ELF" && test -s "$EXPECT"
  chmod 700 "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/header"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  tail -c 11 "$ELF" | cmp - "$TMP/checked.bytes"
  tail -c +121 "$ELF" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm"
  for opcode in 'call' 'ret' 'cmp' 'sete' 'setne' 'syscall'; do
    grep -Fq "$opcode" "$TMP/asm"
  done
  timeout 5s "$ELF" >"$TMP/actual" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$EXPECT" "$TMP/actual"
  test "$(wc -c <"$TMP/actual")" -eq 1
  P=$((P+1))

  # Реальний Linux -EBADF після закриття fd1: жодного фальшивого exit(0).
  code=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/closed.err"
  EBADF=$((EBADF+1))

  # /dev/full повертає -ENOSPC навіть за коректного T5M буфера.
  code=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/full.err"
  ENOSPC=$((ENOSPC+1))

  # Відмова не отруїла наступний запуск того самого байтового ELF.
  timeout 5s "$ELF" >"$TMP/recovered" 2>"$TMP/recovered.err"
  cmp "$EXPECT" "$TMP/recovered"
  test ! -s "$TMP/recovered.err"
  RECOVERY=$((RECOVERY+1))
done
test "$P" -eq 4 && test "$EBADF" -eq 4 && \
  test "$ENOSPC" -eq 4 && test "$RECOVERY" -eq 4
echo 'D3-CALL-WRITE-PASS FPC=checked ELF=4 physical=4 closed=4 full=4 recovery=4 pinned-negative=13 host-negative=12 oracle=EXISTING-SEPARATE energy=NOT-MEASURED'
