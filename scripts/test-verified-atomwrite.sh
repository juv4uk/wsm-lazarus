#!/usr/bin/env bash
# G6 — перевірена машинна D3:010 ATOM T5M відповідь на ET_EXEC.
# Linux stdout/errno — механізм host, не закон SENS. Один чинний FPC CI.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'АТОМ-WRITE-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in fpc git timeout readelf objdump cmp mktemp tail find; do
  command -v "$tool" >/dev/null || {
    echo "АТОМ-WRITE-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 60s bash scripts/check-pin.sh

TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then echo "АТОМ-WRITE-ЗБІЙ рядок=$LINENO код=$rc команда=$BASH_COMMAND" >&2; for log in "$TMP"/compile.log "$TMP"/fixtures.log "$TMP"/fixtures.err; do if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 18 "$log" >&2; fi; done; fi' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
# Потрібен ТОЙ САМИЙ pinned фізичний свідок, що використовує чинний
# test-elfatomt5m.sh. Sparse checkout не повинен змінювати його байти.
PIN=$(git -C external/sens rev-parse HEAD)
timeout 30s git -C external/sens show \
  "$PIN:tests/semantic/d3-eq-atom-boundary-law.sens" \
  >"$TMP/physical/pinned.sens"
test -s "$TMP/physical/pinned.sens"

timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfatomt5m "$ROOT/scripts/test-elfatomt5m.pas" \
  >"$TMP/compile.log" 2>&1 || {
    tail -n 70 "$TMP/compile.log" >&2; exit 1;
  }
timeout 60s "$TMP/bin/test-elfatomt5m" \
  "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2; exit 1;
  }
# Pascal сам перед output вимагає Positives=10/Negatives=16; FPC
# console кирилиця іноді перетворюється на '?', тому лише ASCII-gate.
grep -Fq 'ELF64=10 ' "$TMP/fixtures.log"
test "$(find "$TMP/physical" -maxdepth 1 -type f -name '*.elf' ! -name '*.legacy.elf' | wc -l)" -eq 10

printf '\\x39\\xd0\\x40\\x0f\\x95\\xc7\\x6a\\x3c\\x58\\x0f\\x05' \
  >"$TMP/checked-exit.bin"
COUNT=0; CLOSED=0; FULL=0; RECOVERY=0
for label in атом-нуль атом-один атом-порожній атом-д3-порожній \
  атом-пара атом-пара-порожній атом-пара-пар \
  атом-вкладений-атом-пари атом-атома атом-вкладена-пара; do
  ELF="$TMP/physical/$label.elf"
  LEGACY="$TMP/physical/$label.legacy.elf"
  EXPECT="$TMP/physical/$label.expected.sens"
  test -s "$ELF" && test -s "$LEGACY" && test -s "$EXPECT"
  chmod 700 "$ELF" "$LEGACY"
  timeout 5s readelf -h "$ELF" >"$TMP/header"
  grep -Eq 'Type:.*EXEC' "$TMP/header"
  timeout 5s readelf -l "$ELF" >"$TMP/segments"
  grep -Eq 'LOAD' "$TMP/segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments"
  tail -c 11 "$ELF" | cmp - "$TMP/checked-exit.bin"
  tail -c +121 "$ELF" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm"
  for opcode in 'setne' 'movzx' 'imul' 'syscall'; do
    grep -Fq "$opcode" "$TMP/asm"
  done
  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/actual.err"
  cmp "$EXPECT" "$TMP/actual.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 1
  test ! -s "$TMP/actual.err"
  # Стара ASCII програма підтверджує, що машинний ATOM не підмінено.
  timeout 5s "$LEGACY" >"$TMP/legacy.ascii"
  cmp "$TMP/physical/$label.expected.ascii" "$TMP/legacy.ascii"
  COUNT=$((COUNT+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.sens"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$COUNT" -eq 10 && test "$CLOSED" -eq 10 && \
  test "$FULL" -eq 10 && test "$RECOVERY" -eq 10
echo 'D3-ATOM-ETEXEC-WRITE-PASS fpc=checked elf=10 t5m=10 pinned-negatives=16 closed=10 full=10 recovery=10 oracle=NOT-RUN energy=NOT-MEASURED'
