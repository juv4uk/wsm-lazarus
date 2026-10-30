#!/usr/bin/env bash
# G6.94 — один незмінний ELF64 виконує 32 signed D12 «більше?»
# за один host-frame. Кожен W12 = ОКРЕМИЙ packed T5M atom.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
bash scripts/check-pin.sh
bash scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д12-БІЛЬШЕ-ПАКЕТ-БЛОК: тільки Linux x86-64' >&2; exit 127; }
for c in fpc timeout readelf objdump cmp python3 git sha256sum; do
  command -v "$c" >/dev/null || { echo "Д12-БІЛЬШЕ-ПАКЕТ-БЛОК: бракує $c" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(first-domain . D12)' external/sens/contracts/language-contract-12.lisp
grep -Fq '(11011 (ук більше?) (укр більше?)' external/sens/lib/domains/d5.lisp
# Машинна проєкція є лише у pinned Git blob, не у sparse checkout.
timeout 60s git -C external/sens show \
  "$PIN:lib/machine/profile/current-domain-x86-64.lisp" | \
  grep -Fq "(домен-п'ятий більше? proof \"CMP+SETG+MOVZX"
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for file in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$file" ]]; then echo "--- $file" >&2; tail -30 "$file" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-emit" "$TMP/units-fixture" "$TMP/frames"
for row in \
  'src/sensd12bilshpaket32elf.lpr sensd12bilshpaket32elf units-emit' \
  'scripts/test-elfd12bilshpaket32.pas test-elfd12bilshpaket32 units-fixture'; do
  read -r source target units <<< "$row"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" \
    "-o$target" "$ROOT/$source" >"$TMP/$target.build.log" 2>&1; then
    cat "$TMP/$target.build.log" >&2;exit 1;
  fi
  test -x "$TMP/bin/$target"
done
timeout 30s "$TMP/bin/test-elfd12bilshpaket32" "$TMP/frames" \
  >"$TMP/16-cases.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-BILSH-PAKET32-FIXTURES-OK cases=16 batches=2 negatives=13' \
  "$TMP/fixtures.err"
test "$(wc -l < "$TMP/16-cases.tsv")" -eq 16
ELF="$TMP/d12-greater-batch32.elf"
timeout 10s "$TMP/bin/sensd12bilshpaket32elf" \
  --зібрати-D12-більше-пакет "$ELF" \
  >"$TMP/compiler.log" 2>"$TMP/compiler.err"
test ! -s "$TMP/compiler.err"
grep -Fq 'пар=32 machine=CMP/SETG D1=T5M' "$TMP/compiler.log"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/elf-header.log"
readelf -l "$ELF" >"$TMP/elf-load.log"
grep -Fq 'ELF64' "$TMP/elf-header.log"
grep -Eq 'Type:.*DYN' "$TMP/elf-header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf-header.log"
grep -Fq 'LOAD' "$TMP/elf-load.log"

# Не зашита 32-бітна відповідь, а код реального signed CPU CMP+SETG,
# обидва канонічні W12 LUT і W1 T5M response lookup.
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
data=Path(sys.argv[1]).read_bytes()
assert data[:4]==b'\x7fELF' and data[16:18]==b'\x03\x00'
code=data[120:800]
assert b'\xba\xc1\x00\x00\x00\x4c\x29\xe2\x0f\x05' in code, "не працює read loop до 193"
assert b'\x49\x81\xfc\xc0\x00\x00\x00' in code, "немає повної перевірки 192"
assert b'\x45\x39\xc8\x0f\x9f\xc0\x0f\xb6\xc0' in code, "немає підписаного CMP/SETG/MOVZX"
assert code.count(b'\x41\xc1\xe0\x14')>=1, "немає знакового розширення D12"
assert b'\xba\x20\x00\x00\x00\x0f\x05' in code, "немає одного write(32)"
print("Д12-БІЛЬШЕ-ПАКЕТ-ISA-ГОТОВО read-short=так W12-LUT=так signed-SETG=так")
PY
# Використовуємо звичайний файл для незалежної дизасемблювальної перевірки.
dd if="$ELF" of="$TMP/machine" bs=1 skip=120 count=620 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" \
  >"$TMP/real-disassembly.log"
grep -Eiq 'cmp[[:space:]]+r8d,r9d' "$TMP/real-disassembly.log"
grep -Eiq 'setg[[:space:]]+al' "$TMP/real-disassembly.log"
grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/real-disassembly.log"
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
COUNT=0
for label in batch-a batch-b; do
  test "$(wc -c < "$TMP/frames/$label.frame")" -eq 192
  test "$(wc -c < "$TMP/frames/$label.expected")" -eq 32
  for repeat in 1 2 3 4; do
    timeout 5s "$ELF" <"$TMP/frames/$label.frame" \
      >"$TMP/$label-$repeat.actual" 2>"$TMP/$label-$repeat.err"
    test ! -s "$TMP/$label-$repeat.err"
    cmp "$TMP/frames/$label.expected" "$TMP/$label-$repeat.actual"
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
    COUNT=$((COUNT+32))
  done
done
test "$COUNT" -eq 256

python3 - "$ELF" "$TMP/frames/batch-b.frame" \
  "$TMP/frames/batch-b.expected" <<'PY'
import subprocess,sys,time
from pathlib import Path
exe,source,result=sys.argv[1:]
payload=Path(source).read_bytes()
p=subprocess.Popen([exe],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.stdin
i=0
for size in (1,2,3,5,8,13,21,34,55,13):
    if i==len(payload): break
    block=payload[i:i+size];p.stdin.write(block);p.stdin.flush()
    i+=len(block)
    time.sleep(0.001)
if i<len(payload):p.stdin.write(payload[i:])
p.stdin.close()
code=p.wait(timeout=8)
out=p.stdout.read() if p.stdout else b''
err=p.stderr.read() if p.stderr else b''
assert code==0 and not err and out==Path(result).read_bytes(), (code,err,out)
print("Д12-БІЛЬШЕ-ПАКЕТ-PIPE-ГОТОВО short-reads=так")
PY
NEG=0
reject() {
  local frame="$1" status=0
  timeout 5s "$ELF" <"$frame" \
    >"$TMP/reject-$NEG.stdout" 2>"$TMP/reject-$NEG.err" || status=$?
  if [[ "$status" -ne 2 ]]; then
    echo "Д12-БІЛЬШЕ-ПАКЕТ-БЛОК: невірний exit $status на $frame" >&2;exit 1
  fi
  test ! -s "$TMP/reject-$NEG.stdout"
  grep -Fq 'Д12-БІЛЬШЕ-ПАКЕТ-ВІДМОВА:' "$TMP/reject-$NEG.err"
  NEG=$((NEG+1))
}
for label in empty one-byte short191 short190 extra193 extra194 ascii \
  bad-first bad-middle bad-last bad-third-w2 d7-width ukr-text; do
  reject "$TMP/frames/$label.frame"
done
test "$NEG" -eq 13
cp "$ELF" "$TMP/occupied.elf"
status=0
timeout 10s "$TMP/bin/sensd12bilshpaket32elf" \
  --зібрати-D12-більше-пакет "$TMP/occupied.elf" \
  >"$TMP/no-clobber.stdout" 2>"$TMP/no-clobber.err" || status=$?
test "$status" -eq 2
test ! -s "$TMP/no-clobber.stdout"
grep -Fq 'Д12-БІЛЬШЕ-ПАКЕТ-КОМПІЛЯЦІЯ-ВІДМОВА:' "$TMP/no-clobber.err"
cmp "$ELF" "$TMP/occupied.elf"
timeout 10s "$TMP/bin/sensd12bilshpaket32elf" \
  --зібрати-D12-більше-пакет "$TMP/recovered.elf" > /dev/null
cmp "$ELF" "$TMP/recovered.elf"
timeout 5s "$TMP/recovered.elf" <"$TMP/frames/batch-a.frame" \
  >"$TMP/recovered.actual"
cmp "$TMP/frames/batch-a.expected" "$TMP/recovered.actual"
ORACLE=0
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  python3 - "$SENS_ORACLE_BIN" "$TMP/16-cases.tsv" "$TMP" <<'PY'
from pathlib import Path
import subprocess,sys
oracle,cases,temp=sys.argv[1:]
truth={'0':'НІ','1':'ТАК'}
n=0
for line in Path(cases).read_text().splitlines():
    ident,left,right,bit=line.split('\t')
    form=Path(temp)/f"case-{ident}.lisp"
    form.write_text(f"(більше? {left} {right})\n",encoding='utf-8')
    p=subprocess.run([oracle,str(form)],capture_output=True,timeout=60)
    assert p.returncode==0 and not p.stderr, (ident,p.returncode,p.stderr)
    value=p.stdout.decode('utf-8').strip()
    if value.startswith("sens[укр]> "):value=value[len("sens[укр]> "):].strip()
    values={'0':'НІ','1':'ТАК','НІ':'НІ','ТАК':'ТАК',
            '(н і)':'НІ','(т а к)':'ТАК'}
    assert value in values,(ident,value)
    assert values[value]==truth[bit], (ident,left,right,value,bit)
    n+=1
assert n==16,n
print("Д12-БІЛЬШЕ-ПАКЕТ-ORACLE-ГОТОВО pinned-SENS=16")
PY
  ORACLE=16
fi
echo "Д12-БІЛЬШЕ-ПАКЕТ-ELF-ГОТОВО machine-порівнянь=$COUNT pinned-SENS=$ORACLE негативів=$NEG pipe-short=так no-clobber=так енергія=НЕ-ВИМІРЯНО"
