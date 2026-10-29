#!/usr/bin/env bash
# G6.97: host x86-64 зсуви та обертання; не семантичні SENS оператори.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-ЗСУВ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp mktemp readelf objdump; do
  command -v "$tool" >/dev/null || {
    echo "X64-ЗСУВ-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 80 "$f" >&2; }
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64shift \
  "$ROOT/scripts/test-x64shift.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 45s \
  "$TMP/bin/test-x64shift" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-ЗСУВ-ГОТОВО golden=8 negative=5 recovery=1 as=160 elf=10' \
  "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log" || {
  cat "$TMP/heap.log" >&2; exit 1;
}
# Незалежне асемблювання 120 immediate і 40 CL інструкцій:
# ніякого повторного використання Pascal ModRM розрахунку в oracle.
ops=(shl shr sar rol ror)
regs=(eax ecx edx ebx esp ebp esi edi)
GOLDEN=0
for o in 0 1 2 3 4; do
  for r in 0 1 2 3 4 5 6 7; do
    for count in 3 7 31; do
      printf '.intel_syntax noprefix\n.text\n%s %s, %s\n' \
        "${ops[$o]}" "${regs[$r]}" "$count" >"$TMP/code.s"
      timeout 8s as --64 "$TMP/code.s" -o "$TMP/code.o"
      timeout 8s objcopy -O binary --only-section=.text \
        "$TMP/code.o" "$TMP/reference.bin"
      cmp "$TMP/reference.bin" "$TMP/data/imm-$o-$r-$count.bin" || {
        echo "X64-ЗСУВ-AS-РОЗБІЖНІСТЬ imm=$o/$r/$count" >&2; exit 1;
      }
      GOLDEN=$((GOLDEN+1))
    done
    printf '.intel_syntax noprefix\n.text\n%s %s, cl\n' \
      "${ops[$o]}" "${regs[$r]}" >"$TMP/code.s"
    timeout 8s as --64 "$TMP/code.s" -o "$TMP/code.o"
    timeout 8s objcopy -O binary --only-section=.text \
      "$TMP/code.o" "$TMP/reference.bin"
    cmp "$TMP/reference.bin" "$TMP/data/cl-$o-$r.bin" || {
      echo "X64-ЗСУВ-AS-РОЗБІЖНІСТЬ cl=$o/$r" >&2; exit 1;
    }
    GOLDEN=$((GOLDEN+1))
  done
done
test "$GOLDEN" -eq 160
# Кожен PIE справді виконує host shift / rotation і друкує
# фізичний T5M D1, отриманий через pinned EncodeT5M, не ASCII.
EXECUTED=0
for o in 0 1 2 3 4; do
  for m in 0 1; do
    elf="$TMP/data/elf-$o-$m.elf"
    chmod 700 "$elf"
    timeout 8s readelf -h "$elf" >"$TMP/header.log"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
    timeout 8s readelf -l "$elf" >"$TMP/segment.log"
    ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segment.log"
    tail -c +121 "$elf" >"$TMP/instructions"
    timeout 8s objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/instructions" >"$TMP/disassembly.log"
    grep -Eq "\\b${ops[$o]}\\b" "$TMP/disassembly.log"
    timeout 8s "$elf" >"$TMP/result.sens"
    cmp "$TMP/result.sens" "$TMP/data/elf-$o-$m.sens"
    EXECUTED=$((EXECUTED+1))
  done
done
test "$EXECUTED" -eq 10
echo "X64-ЗСУВ-МАШИНА-ГАРАЗД GNU=$GOLDEN ELF64=$EXECUTED negatives=5 T5M=10 energy=NOT-MEASURED"
