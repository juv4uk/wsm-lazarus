#!/usr/bin/env bash
# G6.257 — перевірений host NEG r32: checked FPC, GNU as, фізичні ELF/T5M.
# Це доказ ISA/codegen, а не закон SENS, D12+ чи незалежний SENS oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'NEG32-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN="${FPC:-fpc}"
for cmd in "$FPC_BIN" as objcopy readelf objdump cmp timeout mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "NEG32-БЛОК: відсутній $cmd" >&2; exit 127;
  }
done
timeout 120s bash "$ROOT/scripts/check-pin.sh"
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 55 "$f" >&2; }
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP" -otest-x64neg32 \
  "$ROOT/scripts/test-x64neg32.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 45s "$TMP/test-x64neg32" "$TMP" \
  >"$TMP/test.log" 2>"$TMP/test.err" || {
    cat "$TMP/test.log" "$TMP/test.err" >&2; exit 1;
  }
grep -Fxq 'G6.257-X64NEG32-PASS matrix=8 golden=2 negative=4 recovery=1 elf=3' "$TMP/test.log"
test ! -s "$TMP/test.err"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"

# Один GNU assembler для всіх 8 регістрів, незалежний від Pascal-кодера.
timeout 30s as --64 "$TMP/matrix.s" -o "$TMP/matrix.o"
timeout 20s objcopy -O binary --only-section=.text "$TMP/matrix.o" "$TMP/gnu.bin"
[[ "$(wc -c <"$TMP/gnu.bin")" == 16 ]]
[[ "$(wc -c <"$TMP/matrix.bin")" == 16 ]]
cmp "$TMP/matrix.bin" "$TMP/gnu.bin"

# Ці ELF виконують NEG/CMP/SETE і записують pinned фізичне W1 через Linux.
for label in zero minus-one mismatch; do
  elf="$TMP/$label.elf"
  test -s "$elf" && test -s "$TMP/$label.expected.sens"
  chmod 700 "$elf"
  timeout 6s readelf -W -h "$elf" >"$TMP/header.log"
  timeout 6s readelf -W -l "$elf" >"$TMP/segments.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  grep -Fq 'LOAD' "$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$elf" >"$TMP/machine.bin"
  timeout 6s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/assembly.log"
  grep -Eq 'neg[[:space:]]+eax' "$TMP/assembly.log"
  timeout 5s "$elf" >"$TMP/answer.sens" 2>"$TMP/answer.err"
  test ! -s "$TMP/answer.err"
  cmp "$TMP/answer.sens" "$TMP/$label.expected.sens"
  test "$(wc -c <"$TMP/answer.sens")" -eq 1

  # Native write повинен повернути exit=1 при fd1 закритому або ENOSPC.
  set +e
  timeout 5s "$elf" >&- 2>/dev/null
  closed_rc=$?
  timeout 5s "$elf" >/dev/full 2>/dev/null
  full_rc=$?
  set -e
  [[ "$closed_rc" == 1 && "$full_rc" == 1 ]] || {
    echo "NEG32-ПРОВАЛ: write $label closed=$closed_rc full=$full_rc" >&2
    exit 1
  }
done
echo 'VERIFIED-X64NEG32-PASS GNU-as=8 bytes=16 golden=2 negative=4 recovery=1 ELF64=3 T5M=byte-exact write=checked energy=NOT-MEASURED'
