#!/usr/bin/env bash
# G6.223 — машинний Linux write guard для pinned D3:101, два W1 stdin атоми.
# Чинний verified-all запускає тест у PR FPC без нового workflow/Rust/apt.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д1-ПОТІК-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump grep mktemp sha256sum wc tail; do
  command -v "$tool" >/dev/null || {
    echo "Д1-ПОТІК-WRITE-БЛОК: бракує $tool" >&2; exit 127;
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
timeout 20s bash "$ROOT/scripts/check-no-lcl.sh"
grep -Fq '(101 (ук тотожне?) (укр тотожне?)' external/sens/lib/domains/d3.lisp

TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then
  echo "Д1-ПОТІК-WRITE-ЗБІЙ: exit=$rc" >&2
  for f in "$TMP"/*.build.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -25 "$f" >&2; fi
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-frames" \
  "$TMP/units-expect" "$TMP/frames" "$TMP/upstream"

for entry in \
  'src/sensd1potikelf.lpr sensd1potikelf units-cli' \
  'scripts/test-elfd1potik.pas test-elfd1potik units-frames' \
  'scripts/test-sensmashyna.pas test-sensmashyna units-expect'; do
  read -r source target units <<< "$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" \
    "-o$target" "$ROOT/$source" >"$TMP/$target.build.log" 2>&1 || {
      tail -50 "$TMP/$target.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$target"
done
timeout 30s "$TMP/bin/test-elfd1potik" "$TMP/frames" \
  >"$TMP/frames.out" 2>"$TMP/frames.err"
grep -Fq 'D1-POTIK-FRAMES-OK pairs=4 negatives=9' "$TMP/frames.out"
timeout 40s "$TMP/bin/test-sensmashyna" external/sens "$TMP/upstream" \
  >"$TMP/upstream.out" 2>"$TMP/upstream.err"
grep -Fq 'МАШИНА-СВІДКИ-ГАРАЗД фізичних=8' "$TMP/upstream.out"

ELF="$TMP/д1-потік.elf"
timeout 20s "$TMP/bin/sensd1potikelf" --зібрати-D1-потік "$ELF" \
  >"$TMP/compiler.out" 2>"$TMP/compiler.err"
test ! -s "$TMP/compiler.err" && test -x "$ELF"
grep -Fq 'machine=CMP/SETE/MOVZX' "$TMP/compiler.out"
timeout 5s readelf -h "$ELF" >"$TMP/header.txt"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.txt"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.txt"

# Незалежний дизасемблер: повний 64-бітний RAX, а не лише AL,
# та справжній перехід після sys_write. Жодного host enum/закону.
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  --adjust-vma=0 "$ELF" >"$TMP/raw-disassembly.txt" || true
# Сирі ELF заголовки не слід декодувати як код: пропускаємо 120 байтів.
tail -c +121 "$ELF" | head -c 320 >"$TMP/machine.bin" || true
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine.bin" >"$TMP/machine.dis"
grep -Eiq 'cmp[[:space:]]+rax,0x1' "$TMP/machine.dis"
grep -Eiq 'jne[[:space:]]' "$TMP/machine.dis"
grep -Eiq 'sete[[:space:]]+al' "$TMP/machine.dis"
grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/machine.dis"

HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
GOOD=0
BAD=0
RECOVERY=0
for label in тотожні-00 тотожні-01 тотожні-10 тотожні-11; do
  frame="$TMP/frames/$label.frame"
  expected="$TMP/upstream/$label.expected.sens"
  timeout 5s "$ELF" <"$frame" >"$TMP/actual.sens" 2>"$TMP/run.err"
  test ! -s "$TMP/run.err"
  cmp "$expected" "$TMP/actual.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 1
  GOOD=$((GOOD+1))

  rc=0
  timeout 5s "$ELF" <"$frame" 1>&- 2>"$TMP/run.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/run.err"
  BAD=$((BAD+1))

  rc=0
  timeout 5s "$ELF" <"$frame" >/dev/full 2>"$TMP/run.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/run.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" <"$frame" >"$TMP/recovered.sens" 2>"$TMP/run.err"
  test ! -s "$TMP/run.err"
  cmp "$expected" "$TMP/recovered.sens"
  test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  RECOVERY=$((RECOVERY+1))
done

REJECT=0
for label in short extra bad-byte; do
  rc=0
  timeout 5s "$ELF" <"$TMP/frames/$label.frame" \
    >"$TMP/reject.sens" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.sens"
  grep -Fq 'Д1-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
  REJECT=$((REJECT+1))
done

test "$GOOD" -eq 4 && test "$BAD" -eq 8 &&
  test "$RECOVERY" -eq 4 && test "$REJECT" -eq 3
echo "Д1-ПОТІК-WRITE-PASS positives=$GOOD write-negatives=$BAD recovery=$RECOVERY input-negatives=$REJECT physical=D1-T5M machine=CMP/SETE/CMP/JNE oracle=NOT-RUN energy=NOT-MEASURED"
