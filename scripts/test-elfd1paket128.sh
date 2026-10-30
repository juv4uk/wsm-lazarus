#!/usr/bin/env bash
# G6.90 — один фізичний ELF64 виконує 128 D3:101 рівностей за запуск.
# .frame = host конкатенація 256 окремих T5M W1 атомів, НЕ .sens форма.
# .result = host конкатенація 128 окремих packed D1 W1, НЕ .sens форма.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д1-ПАКЕТ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for tool in fpc git timeout cmp readelf objdump dd python3 sha256sum; do
  command -v "$tool" >/dev/null || { echo "Д1-ПАКЕТ-БЛОК: немає $tool" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(101 (ук тотожне?) (укр тотожне?)' external/sens/lib/domains/d3.lisp
grep -Fq '(eq-result . (D1:0 D1:1))' external/sens/contracts/language-contract-12.lisp
grep -Fq '(eq-operands . admitted-atoms-only)' external/sens/contracts/language-contract-12.lisp
timeout 60s git -C external/sens show \
  "$PIN:lib/machine/profile/current-domain-x86-64.lisp" | \
  grep -Fq '(домен-третій тотожне? direct "CMP/SETE")'
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for p in "$TMP"/*.build.log "$TMP"/*.err; do if [[ -s "$p" ]]; then echo "--- $p" >&2; tail -28 "$p" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units-kernel" "$TMP/units-fixture" "$TMP/units-witness" \
  "$TMP/bin" "$TMP/frames" "$TMP/свідки"
for row in \
  'src/sensd1paket128elf.lpr sensd1paket128elf units-kernel' \
  'scripts/test-elfd1paket128.pas test-elfd1paket128 units-fixture' \
  'scripts/test-sensmashyna.pas test-sensmashyna units-witness'; do
  read -r source name unitdir <<< "$row"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/$unitdir" -FE"$TMP/bin" \
      "-o$name" "$ROOT/$source" >"$TMP/$name.build.log" 2>&1; then
    cat "$TMP/$name.build.log" >&2
    exit 1
  fi
  test -x "$TMP/bin/$name"
done

timeout 30s "$TMP/bin/test-elfd1paket128" "$TMP/frames" >"$TMP/fixture.log"
grep -Fq 'D1-BATCH128-FRAMES-OK sets=2 each=128 negatives=12' "$TMP/fixture.log"
# Діючий незалежний фізичний виконавець дає лише чотири canonical
# приклади; pinned REPL підтверджує ті самі форми на наступному етапі.
timeout 40s "$TMP/bin/test-sensmashyna" external/sens "$TMP/свідки" \
  >"$TMP/witness.log"
python3 - "$TMP/frames" "$TMP/свідки" <<'PY'
from pathlib import Path
import sys
frames,witness=map(Path,sys.argv[1:])
truth={}
for n,case in enumerate(("тотожні-00","тотожні-01","тотожні-10","тотожні-11")):
    p=witness/f"{case}.expected.sens"
    raw=p.read_bytes()
    assert len(raw)==1, (case,len(raw))
    truth[str(n)]=raw
for name in ("batch-a","batch-b"):
    order=(frames/f"{name}.order").read_bytes()
    src=(frames/f"{name}.frame").read_bytes()
    assert len(order)==128 and len(src)==256
    assert set(order)==set(b"0123"), "неповна четвірка D3 EQ"
    expected=b"".join(truth[chr(k)] for k in order)
    assert len(expected)==128
    (frames/f"{name}.expected").write_bytes(expected)
print("Д1-ПАКЕТ-ЕТАЛОНИ-ГОТОВО pinned-матриця=4 фізичних-пар=256")
PY

ELF="$TMP/пакетне-ядро.elf"
timeout 15s "$TMP/bin/sensd1paket128elf" --зібрати-пакет-D1 "$ELF" \
  >"$TMP/build.status" 2>"$TMP/build.err"
test ! -s "$TMP/build.err"
grep -Fq 'машинні-пари=128 фізичні-W1=так' "$TMP/build.status"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/header.txt"
grep -Fq 'ELF64' "$TMP/header.txt"
grep -Eq 'Type:.*DYN' "$TMP/header.txt"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.txt"
readelf -l "$ELF" | grep -Fq LOAD
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
d=Path(sys.argv[1]).read_bytes()
assert d[:4]==b"\x7fELF" and d[16:18]==b"\x03\x00"
code=d[120:]
assert b"\xba\x01\x01\x00\x00\x4c\x29\xe2\x0f\x05" in code, "немає loop read(0,remaining)"
assert b"\x3a\x44\x1c\x01\x0f\x94\xc0\x0f\xb6\xc0" in code, "немає runtime CMP/SETE/MOVZX"
assert b"\xba\x80\x00\x00\x00\x0f\x05" in code, "немає одного stdout write(128)"
assert b"\x49\x81\xfc\x00\x01\x00\x00" in code, "немає перевірки exact 256"
print("Д1-ПАКЕТ-MACHINE-OPCODES-OK read-loop=так CMP/SETE=так write=128")
PY
dd if="$ELF" of="$TMP/instructions" bs=1 skip=120 count=280 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/instructions" \
  >"$TMP/disassembly.txt"
grep -Eiq 'sete[[:space:]]+al' "$TMP/disassembly.txt"
grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/disassembly.txt"
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
PASS=0
for name in batch-a batch-b; do
  for repeat in 1 2 3 4; do
    timeout 5s "$ELF" <"$TMP/frames/$name.frame" \
      >"$TMP/$name-$repeat.actual" 2>"$TMP/$name-$repeat.err"
    test ! -s "$TMP/$name-$repeat.err"
    cmp "$TMP/frames/$name.expected" "$TMP/$name-$repeat.actual"
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
    PASS=$((PASS+128))
  done
done
test "$PASS" -eq 1024
# Справжній Linux pipe із короткими write надходженнями: kernel read
# може повернути менше запитаного; це НЕ EOF і не мовна помилка.
python3 - "$ELF" "$TMP/frames/batch-b.frame" \
   "$TMP/frames/batch-b.expected" <<'PY'
import subprocess,sys,time
from pathlib import Path
elf,src,expected=sys.argv[1:]
payload=Path(src).read_bytes()
p=subprocess.Popen([elf],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.stdin is not None
at=0
for n in (1,2,3,5,8,13,21,34,55,89,25):
    if at>=len(payload): break
    block=payload[at:at+n]
    p.stdin.write(block)
    p.stdin.flush()
    at+=len(block)
    time.sleep(0.003)
if at<len(payload):
    p.stdin.write(payload[at:])
p.stdin.close()
code=p.wait(timeout=8)
out=p.stdout.read() if p.stdout else b""
err=p.stderr.read() if p.stderr else b""
assert code==0 and not err, (code,err)
assert out==Path(expected).read_bytes()
print("Д1-ПАКЕТ-PIPE-ЧАСТКОВІ-ЧИТАННЯ-ГАРАЗД")
PY

NEG=0
reject() {
  local frame="$1" actual="$TMP/reject-$NEG.stdout" diagnostic="$TMP/reject-$NEG.err"
  local status=0
  timeout 5s "$ELF" <"$frame" >"$actual" 2>"$diagnostic" || status=$?
  test "$status" -eq 2 || {
    echo "Д1-ПАКЕТ-ВІДМОВА: очікували exit 2 для $frame, маємо $status" >&2; exit 1; }
  test ! -s "$actual"
  grep -Fq 'Д1-ПАКЕТ-ВІДМОВА:' "$diagnostic"
  NEG=$((NEG+1))
}
for case in empty one-byte odd-255 extra-257 extra-258 ascii \
  invalid-first invalid-middle invalid-last d7-one invalid-variant noncanonical-text; do
  reject "$TMP/frames/$case.frame"
done
test "$NEG" -eq 12
cp "$ELF" "$TMP/occupied.elf"
STATUS=0
timeout 15s "$TMP/bin/sensd1paket128elf" --зібрати-пакет-D1 \
  "$TMP/occupied.elf" >"$TMP/no-clobber.stdout" \
  2>"$TMP/no-clobber.err" || STATUS=$?
test "$STATUS" -eq 2
test ! -s "$TMP/no-clobber.stdout"
grep -Fq 'Д1-ПАКЕТ-КОМПІЛЯЦІЯ-ВІДМОВА:' "$TMP/no-clobber.err"
cmp "$ELF" "$TMP/occupied.elf"
timeout 15s "$TMP/bin/sensd1paket128elf" --зібрати-пакет-D1 \
  "$TMP/recovered.elf" > /dev/null
cmp "$ELF" "$TMP/recovered.elf"
timeout 5s "$TMP/recovered.elf" <"$TMP/frames/batch-a.frame" \
  >"$TMP/recovered.actual"
cmp "$TMP/frames/batch-a.expected" "$TMP/recovered.actual"

if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  # Не створюємо другу модель D3:101. Існуючий benchmark-native-d3
  # для чотирьох фізичних source форм проводить незалежне REPL
  # звіряння pinned binary result; host-пакети лише повторюють їх.
  timeout 1800s env SENS_BENCH_REPEATS=3 \
    bash scripts/benchmark-native-d3.sh >"$TMP/oracle.log" 2>"$TMP/oracle.err" || {
    cat "$TMP/oracle.log" "$TMP/oracle.err" >&2; exit 1; }
  python3 - <<'PY'
import json
from pathlib import Path
d=json.loads(Path("build/m0.2/benchmark-native-d3/виміри.json").read_text(encoding="utf-8"))
assert d["незалежний_SENS_SHA"]=="2c498b35af53c085450eac6f51b87facf7f9aa47"
assert len(d["форми"])==4 and d["негативів_компаратора"]==7
assert all(s in '\n'.join(str(f) for f in d["форми"]) for s in
    ["тотожні-00","тотожні-01","тотожні-10","тотожні-11"])
print("Д1-ПАКЕТ-НЕЗАЛЕЖНИЙ-SENS-REPL-ГАРАЗД source=4 batch-обчислень=1024")
PY
fi
echo "Д1-ПАКЕТ-ELF-ГАРАЗД пар=$PASS пакетів=2 негативів=$NEG Linux-read-short=так same-ELF=так no-clobber=так SENS=PINNED енергія=НЕ-ВИМІРЯНО"
