#!/usr/bin/env bash
# G6.88 — один незмінний ELF64, 26 machine D12 ADD та pinned SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Д12-ПОТІК-БЛОК: Linux x86-64' >&2; exit 127; }
for tool in fpc python3 cmp readelf objdump timeout git sha256sum grep wc; do
  command -v "$tool" >/dev/null || { echo "Д12-ПОТІК-БЛОК: бракує $tool" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
ORACLE=$(printenv SENS_ORACLE_BIN || true)
test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
grep -Fq '(semantic-identity . (exact-domain exact-width exact-bit-word admitted-law))' \
  external/sens/contracts/language-contract-12.lisp
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then for f in "$TMP"/*.build.log "$TMP"/*.err; do if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -25 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-kernel" "$TMP/units-fixtures" "$TMP/units-number" "$TMP/frames"
for row in \
  'src/sensd12potikelf.lpr sensd12potikelf units-kernel' \
  'scripts/test-elfd12potik.pas test-elfd12potik units-fixtures' \
  'src/senschyslo.lpr senschyslo units-number'; do
  read -r source exe units <<< "$row"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$exe" \
      "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1; then
    cat "$TMP/$exe.build.log" >&2; exit 1
  fi
  test -x "$TMP/bin/$exe"
done
timeout 30s "$TMP/bin/test-elfd12potik" "$TMP/frames" \
  >"$TMP/valid.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'Д12-ПОТІК-СВІДКИ-ГОТОВО позитивів=13 переповнень=3 фізичних-негативів=12' "$TMP/fixtures.err"
test "$(wc -l < "$TMP/valid.tsv")" -eq 13
ELF="$TMP/динамічний-д12.elf"
timeout 15s "$TMP/bin/sensd12potikelf" --зібрати-D12-потік "$ELF" \
  >"$TMP/compile.stdout" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err"
grep -Fq 'Д12-ПОТІК-ELF-ГОТОВО' "$TMP/compile.stdout"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/header.log"
readelf -l "$ELF" >"$TMP/program.log"
grep -Fq 'ELF64' "$TMP/header.log"
grep -Eq 'Type:.*DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
grep -Fq 'LOAD' "$TMP/program.log"
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
b = Path(sys.argv[1]).read_bytes()
code = b[120:540]
assert b[:4] == b'\x7fELF' and b[16:18] == b'\x03\x00'
assert b'\xba\x07\x00\x00\x00\x0f\x05' in code, 'немає read(0,buf,7)'
assert b'\x48\x83\xf8\x06\x0f\x85' in code, 'немає exact length gate'
assert b'\x44\x89\xc0\x44\x01\xc8\x3d\xff\x07\x00\x00' in code, 'немає CPU ADD'
assert b'\x3d\x00\xf8\xff\xff\x0f\x8c' in code, 'немає signed overflow guard'
assert b'\x0f\xb6\x04\x06' in code, 'немає T5M decoder lookup'
assert b'\x8a\x04\x06' in code, 'немає T5M encoder lookup'
print('Д12-ПОТІК-ІНСТРУКЦІЇ-ГАРАЗД read=7 ADD=CPU overflow=gate T5M=lookup')
PY
dd if="$ELF" of="$TMP/machine" bs=1 skip=120 count=410 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" >"$TMP/disassembly.log"
grep -Eiq 'add[[:space:]]+eax,r9d' "$TMP/disassembly.log"
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
COUNT=0
ORACLE_COUNT=0
while IFS=$'\t' read -r name left right; do
  test -n "$name"
  for round in 1 2; do
    timeout 5s "$ELF" <"$TMP/frames/$name.frame" \
      >"$TMP/$name.$round.actual.sens" 2>"$TMP/$name.$round.err"
    test ! -s "$TMP/$name.$round.err"
    cmp "$TMP/frames/$name-expected.sens" "$TMP/$name.$round.actual.sens"
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
    COUNT=$((COUNT+1))
  done
  cmp "$TMP/$name.1.actual.sens" "$TMP/$name.2.actual.sens"
  "$TMP/bin/senschyslo" --в-укр D12 "$TMP/$name.1.actual.sens" \
    >"$TMP/$name.machine.lisp"
  printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$name.expression.lisp"
  timeout 60s "$ORACLE" "$TMP/$name.expression.lisp" \
    >"$TMP/$name.oracle.lisp" 2>"$TMP/$name.oracle.err"
  test ! -s "$TMP/$name.oracle.err"
  cmp "$TMP/$name.oracle.lisp" "$TMP/$name.machine.lisp"
  "$TMP/bin/senschyslo" --з-укр D12 "$TMP/$name.oracle.lisp" \
    "$TMP/$name.oracle.sens" >"$TMP/$name.mint.out"
  test ! -s "$TMP/$name.mint.out"
  cmp "$TMP/$name.oracle.sens" "$TMP/$name.1.actual.sens"
  ORACLE_COUNT=$((ORACLE_COUNT+1))
done <"$TMP/valid.tsv"
test "$COUNT" -eq 26 && test "$ORACLE_COUNT" -eq 13
NEG=0
reject() {
  local frame=$1 output="$TMP/negative-$NEG.sens"
  local error="$TMP/negative-$NEG.err" status=0
  timeout 5s "$ELF" <"$TMP/frames/$frame.frame" >"$output" 2>"$error" || status=$?
  if [[ "$status" -ne 2 ]]; then echo "Д12-ПОТІК-EXIT-НЕВІРНИЙ: $frame code=$status" >&2; exit 1; fi
  test ! -s "$output"
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$error"
  NEG=$((NEG+1))
}
for frame in overflow-up overflow-down overflow-wide empty short1 short5 \
  extra invalid243 badfirst badsecond badthird badlast newline projection d1; do
  reject "$frame"
done
test "$NEG" -eq 15
cp "$ELF" "$TMP/зайнятий.elf"
STATUS=0
timeout 10s "$TMP/bin/sensd12potikelf" --зібрати-D12-потік \
  "$TMP/зайнятий.elf" >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || STATUS=$?
test "$STATUS" -eq 2 && test ! -s "$TMP/no-clobber.out"
grep -Fq 'Д12-ПОТІК-КОМПІЛЯЦІЯ-ВІДМОВА:' "$TMP/no-clobber.err"
cmp "$ELF" "$TMP/зайнятий.elf"
timeout 10s "$TMP/bin/sensd12potikelf" --зібрати-D12-потік \
  "$TMP/recovered.elf" >/dev/null
cmp "$ELF" "$TMP/recovered.elf"
timeout 5s "$TMP/recovered.elf" <"$TMP/frames/01.frame" >"$TMP/recovered.sens"
cmp "$TMP/frames/01-expected.sens" "$TMP/recovered.sens"
echo "Д12-ПОТІК-ГАРАЗД ELF=1 виконань=$COUNT pinned-SENS=$ORACLE_COUNT негативів=$NEG no-clobber=так dynamic-D12=так T5M=точно RAPL=НЕ-ВИМІРЯНО"
