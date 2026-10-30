#!/usr/bin/env bash
# G6: машинне підтвердження повного stdout для 32 змішаних D5 дерев.
# Лише Linux ABI: exit(2) після -EBADF/-ENOSPC, без нового закону SENS.
# Oracle pinned SENS перевіряє окремий scripts/test-irarithderevo.sh.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-ДЕРЕВО-STDOUT-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc git timeout cmp readelf grep mktemp wc tail; do
  command -v "$tool" >/dev/null || {
    echo "Д5-ДЕРЕВО-STDOUT-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
cleanup() {
  local rc=$? log
  if (( rc != 0 )); then
    echo "Д5-ДЕРЕВО-STDOUT-ЗБІЙ код=$rc" >&2
    for log in "$TMP"/*.log "$TMP"/*.err; do
      if [[ -s "$log" ]]; then
        echo "--- $log" >&2
        tail -n 35 "$log" >&2
      fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
# Генератор: запозичені фізичні .sens і 32 ELF, а не нові Pascal закони.
# Входи FPC — pinned T5M; керовані RawByteString живуть лише під час
# компіляції. Результат процесу ELF — owned три фізичні байти D12/T5M.
# Питання: чому stdout не є доказом нового закону?
# Чому -EBADF і -ENOSPC мають завершувати процес з помилкою?
# Чому повторне виконання перевіряє відсутність пошкодженого стану?
# Де незалежно звіряється семантика кожного числа?
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-irarithderevo "$ROOT/scripts/test-irarithderevo.pas" \
  >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2
    exit 1
  }
test -x "$TMP/bin/test-irarithderevo"
HEAPTRC="log=$TMP/heap.log" timeout 120s \
  "$TMP/bin/test-irarithderevo" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Eq 'positive=32[[:space:]]+negative=17' "$TMP/generator.log"
if [[ -s "$TMP/heap.log" ]]; then
  grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
fi
test -s "$TMP/physical/cases.tsv"
PASS=0
CLOSED=0
FULL=0
RECOVERY=0
while IFS=$'\t' read -r label steps; do
  [[ "$label" =~ ^[0-3]-([1-9]|[12][0-9]|3[01])$ ]]
  test "$steps" -ge 1 && test "$steps" -le 31
  ELF="$TMP/physical/$label.elf"
  EXPECT="$TMP/physical/$label.expected.sens"
  test -s "$ELF" && test -s "$EXPECT"
  test "$(wc -c <"$EXPECT")" -eq 3
  timeout 5s readelf -h "$ELF" >"$TMP/header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  chmod 700 "$ELF"
  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/positive.err"
  test ! -s "$TMP/positive.err"
  cmp "$EXPECT" "$TMP/actual.sens"
  PASS=$((PASS+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
  test ! -s "$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.sens"
  RECOVERY=$((RECOVERY+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 32 && test "$CLOSED" -eq 32 && \
  test "$FULL" -eq 32 && test "$RECOVERY" -eq 32
echo 'Д5-ДЕРЕВО-STDOUT-PASS fpc=checked physical=32 admission-negatives=17 closed=32 full=32 recovery=32 oracle=NOT-RUN energy=NOT-MEASURED'
