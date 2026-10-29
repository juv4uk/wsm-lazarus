#!/usr/bin/env bash
# G6.85: один СТАЛИЙ машинний ELF ядро; чотири нові ДИНАМІЧНІ
# фізичні парні входи. Кожний кадр = concatenation ДВОХ окремих
# canonical W1 .sens файлів, ніколи не один SENS .sens документ.
# Без host Boolean або повторного Pascal evaluator всередині ELF.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д1-ДИНАМІЧНИЙ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in fpc git timeout cmp readelf objdump python3 sha256sum; do
  command -v "$exe" >/dev/null || {
    echo "Д1-ДИНАМІЧНИЙ-ELF-БЛОК: бракує $exe" >&2; exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
grep -Fq '(101 (ук тотожне?) (укр тотожне?)' external/sens/lib/domains/d3.lisp
grep -Fq '(eq-result . (D1:0 D1:1))' external/sens/contracts/language-contract-12.lisp
grep -Fq '(eq-operands . admitted-atoms-only)' external/sens/contracts/language-contract-12.lisp
grep -Fq '(semantic-identity . (exact-domain exact-width exact-bit-word admitted-law))' \
  external/sens/contracts/language-contract-12.lisp
# Машинний профіль НЕ входить до sparse checkout і читається
# безпосередньо з Git blob точного pinned SENS source SHA.
timeout 60s git -C external/sens show \
  "$PIN:lib/machine/profile/current-domain-x86-64.lisp" | \
  grep -Fq '(домен-третій тотожне? direct "CMP/SETE")'
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then for file in "$TMP"/*.build.log "$TMP"/*.err; do if [[ -s "$file" ]]; then echo "--- $file" >&2; tail -30 "$file" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-kernel" "$TMP/units-frames" \
  "$TMP/units-expect" "$TMP/frames" "$TMP/upstream"
for entry in \
  'src/sensd1potikelf.lpr sensd1potikelf units-kernel' \
  'scripts/test-elfd1potik.pas test-elfd1potik units-frames' \
  'scripts/test-sensmashyna.pas test-sensmashyna units-expect'; do
  read -r source name units <<< "$entry"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" \
      "-o$name" "$ROOT/$source" >"$TMP/$name.build.log" 2>&1; then
    cat "$TMP/$name.build.log" >&2; exit 1
  fi
  test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd1potik" "$TMP/frames" >"$TMP/frames.log"
grep -Fq 'D1-POTIK-FRAMES-OK pairs=4 negatives=9' "$TMP/frames.log"
# Семантична відповідь — уже злитий D3 TBinaryExecutor для тих
# САМИХ 4 програм, а незалежний SENS REPL окремо засвідчить їх.
timeout 40s "$TMP/bin/test-sensmashyna" external/sens \
  "$TMP/upstream" >"$TMP/upstream.log"
ELF="$TMP/динамічна-тотожність.elf"
timeout 15s "$TMP/bin/sensd1potikelf" --зібрати-D1-потік "$ELF" \
  >"$TMP/compile.log" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err"
grep -Fq 'machine=CMP/SETE/MOVZX' "$TMP/compile.log"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/elf-header.log"
readelf -l "$ELF" >"$TMP/elf-program.log"
grep -Fq 'ELF64' "$TMP/elf-header.log"
grep -Eq 'Type:.*DYN' "$TMP/elf-header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf-header.log"
grep -Fq 'LOAD' "$TMP/elf-program.log"
# Механічна перевірка, що Є справжні syscall read + CMP/SETE/MOVZX,
# а НЕ заздалегідь вбудовані 4 відповіді або текстові функції.
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
d = Path(sys.argv[1]).read_bytes()
code = d[120:260]
assert d[:4] == b'\x7fELF' and d[16:18] == b'\x03\x00'
assert b'\xbA\x03\x00\x00\x00\x0F\x05' in code, 'немає машинного read(0,buf,3)'
assert b'\x3A\x44\x24\x01\x0F\x94\xC0\x0F\xB6\xC0' in code, 'немає signed-binary CMP/SETE'
assert b'\x48\x83\xF8\x02\x0F\x85' in code, 'немає exact length admission'
assert b'\x0F\xB6\x04\x06' in code, 'немає T5M indexed lookup'
print('Д1-ДИНАМІЧНИЙ-ELF-INSTRUCTIONS-OK read=3 CMP=1 SETE=1')
PY
dd if="$ELF" of="$TMP/instructions" bs=1 skip=120 count=130 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/instructions" \
  >"$TMP/disassembly.log"
grep -Eiq 'sete[[:space:]]+al' "$TMP/disassembly.log"
grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/disassembly.log"
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
COUNT=0
for round in 1 2 3; do
  for label in тотожні-00 тотожні-01 тотожні-10 тотожні-11; do
    # Той самий executable kernel у кожному запуску.
    timeout 5s "$ELF" <"$TMP/frames/$label.frame" \
      >"$TMP/$label.$round.actual.sens" 2>"$TMP/$label.$round.err"
    test ! -s "$TMP/$label.$round.err"
    cmp "$TMP/upstream/$label.expected.sens" "$TMP/$label.$round.actual.sens"
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 12
NEG=0
reject() {
  local input="$1" output="$TMP/negative-$NEG.sens" err="$TMP/negative-$NEG.err"
  local result=0
  timeout 5s "$ELF" <"$input" >"$output" 2>"$err" || result=$?
  if [[ "$result" -ne 2 ]]; then
    echo "Д1-ДИНАМІЧНИЙ-ELF-БЛОК: не той exit для $input: $result" >&2
    exit 1
  fi
  test ! -s "$output"
  grep -Fq 'Д1-ПОТІК-ВІДМОВА:' "$err"
  NEG=$((NEG+1))
}
for label in empty short extra bad-byte ASCII \
  bad-first bad-second d7 extra-zero; do
  reject "$TMP/frames/$label.frame"
done
printf '(тотожне? так ні)\n' >"$TMP/текстова.lisp"
reject "$TMP/текстова.lisp"
test "$NEG" -eq 10
# Guard вихідного ELF: no-clobber і незалежність від провалених stdin.
cp "$ELF" "$TMP/зайнятий.elf"
STATUS=0
timeout 10s "$TMP/bin/sensd1potikelf" --зібрати-D1-потік \
  "$TMP/зайнятий.elf" >"$TMP/occupied.stdout" 2>"$TMP/occupied.err" || STATUS=$?
test "$STATUS" -eq 2
test ! -s "$TMP/occupied.stdout"
grep -Fq 'Д1-ПОТІК-КОМПІЛЯЦІЯ-ВІДМОВА:' "$TMP/occupied.err"
cmp "$ELF" "$TMP/зайнятий.elf"
timeout 10s "$TMP/bin/sensd1potikelf" --зібрати-D1-потік \
  "$TMP/після-відмови.elf" >/dev/null
cmp "$ELF" "$TMP/після-відмови.elf"
timeout 5s "$TMP/після-відмови.elf" <"$TMP/frames/тотожні-11.frame" \
  >"$TMP/recovered.sens"
cmp "$TMP/upstream/тотожні-11.expected.sens" "$TMP/recovered.sens"
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  # УЖЕ злитий стенд виконує ті ж чотири фізичні pinned D3:101 source
  # форми й independently порівнює їх з цим Rust/Zig REPL.
  timeout 1800s bash scripts/benchmark-native-d3.sh
  python3 - <<'PY'
import json
from pathlib import Path
p=Path('build/m0.2/benchmark-native-d3/виміри.json')
z=json.loads(p.read_text(encoding='utf-8'))
assert z['незалежний_SENS_SHA']=='1f1bf676eeac605e065035d9dd2adaae807f1788'
n=[str(x) for x in z['форми']]
assert len(n)==4 and all(s in '\n'.join(n) for s in ['тотожні-00','тотожні-01','тотожні-10','тотожні-11'])
assert z['негативів_компаратора']==7
print('Д1-ДИНАМІЧНИЙ-ELF-ORACLE-OK pinned REPL=4 exact physical sources=4')
PY
fi
echo "Д1-ДИНАМІЧНИЙ-ELF-ГАРАЗД машинних-виконань=$COUNT різних-пар=4 негативів=$NEG no-clobber=так executor=один D1=T5M енергія=НЕ-ВИМІРЯНО"
