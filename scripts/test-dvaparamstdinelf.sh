#!/usr/bin/env bash
# G6.175 — два фізичні D24 runtime аргументи до ОДНОГО готового ELF.
# Два pinned-фізичні D5 тіла ADD/SUB, жодної host-арифметики в backend.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for cmd in fpc git as objcopy python3 timeout readelf cmp mktemp stat grep wc;do
  command -v "$cmd" >/dev/null || { echo "НЕМАЄ: $cmd" >&2;exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
ORACLE_MODE="${SENS_ORACLE_MODE:-full}"
case "$ORACLE_MODE" in full|native) ;; *) echo "НЕВІДОМИЙ-РЕЖИМ: $ORACLE_MODE" >&2;exit 2;; esac
ORACLE=''
if [[ "$ORACLE_MODE" == full ]];then
  ORACLE="${SENS_ORACLE_BIN:-}"
  [[ -n "$ORACLE" && -x "$ORACLE" ]] || {
    echo "ПОТРІБЕН-ПРИВ'ЯЗАНИЙ-ПОВНИЙ-SENS-ОРАКУЛ" >&2;exit 2;
  }
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
cleanup() {
  rc=$?
  if ((rc));then
    echo "ДВА-D24-STDIN-ПРОВАЛ rc=$rc" >&2
    for file in "$TMP"/*.err "$TMP"/*.build;do
      [[ ! -s "$file" ]] || { echo "-- $file" >&2;tail -n 25 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/u" "$TMP/b" "$TMP/cases" "$TMP/n"
timeout 30s as -o "$TMP/stub.o" scripts/dvaparam-t5mstdin-x86-64.S
timeout 30s objcopy -j .text -O binary "$TMP/stub.o" "$TMP/stub.bin"
python3 - "$TMP/stub.bin" src/wsm.bodytwot5mstdin.pas <<'PY'
from pathlib import Path
import sys,re
actual=Path(sys.argv[1]).read_bytes()
text=Path(sys.argv[2]).read_text()
source=text.split("StubHex=",1)[1].split(";\n  StdoutPrefix:",1)[0]
embedded=bytes.fromhex("".join(re.findall(r"'([0-9a-f]+)'",source)))
assert len(actual)==658 and actual==embedded,(len(actual),len(embedded))
assert actual[111:116]==b'\xe9\0\0\0\0'
print("ДВА-D24-АСЕМБЛЕР-PASS bytes=658 jmp=111")
PY
for spec in \
  'src/sensbodyfileelf.lpr:sensbodyfileelf' \
  'src/sensdvaparamstdinelf.lpr:sensdvaparamstdinelf' \
  'src/senschyslo.lpr:senschyslo' \
  'scripts/test-bodyfile-compiler.pas:test-bodyfile-compiler';do
  IFS=: read -r source name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2;exit 1;
    }
  test -x "$TMP/b/$name"
done
timeout 60s "$TMP/b/test-bodyfile-compiler" "$ROOT" "$TMP/cases" \
  >"$TMP/manifest" 2>"$TMP/fixtures.err"
test "$(wc -l <"$TMP/manifest")" -eq 9
grep -Fq 'BODY-FILE-FIXTURES-OK cases=9 negatives=5' "$TMP/fixtures.err"
for op in add7 sub7;do
  base="$TMP/cases/$op"
  timeout 60s "$TMP/b/sensbodyfileelf" --два-D24-stdout \
    "$base.body.sens" "$base.p1.sens" "$base.p2.sens" \
    "$base.a1.sens" "$base.a2.sens" "$TMP/$op.static.elf" \
    >"$TMP/$op.compiled" 2>"$TMP/$op.compile.err"
  test ! -s "$TMP/$op.compile.err"
  grep -Fq 'result=D24_T5M_STDOUT' "$TMP/$op.compiled"
  timeout 60s "$TMP/b/sensdvaparamstdinelf" --два-фізичні-D24-stdin \
    "$TMP/$op.static.elf" "$TMP/$op.dynamic.elf" \
    >"$TMP/$op.postpass" 2>"$TMP/$op.postpass.err"
  test ! -s "$TMP/$op.postpass.err"
  grep -Fq 'args=2 exact=D24 input=10-byte-T5M' "$TMP/$op.postpass"
  test "$(stat -c '%a' "$TMP/$op.dynamic.elf")" = 700
  readelf -h "$TMP/$op.dynamic.elf" >"$TMP/$op.header"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$op.header"
  if readelf -l "$TMP/$op.dynamic.elf" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'НЕПРИПУСТИМИЙ-ELF-DYNAMIC-LOADER' >&2;exit 1;
  fi
  timeout 60s "$TMP/b/sensdvaparamstdinelf" --два-фізичні-D24-stdin \
    "$TMP/$op.static.elf" "$TMP/$op.again.elf" >"$TMP/$op.again.log"
  cmp "$TMP/$op.dynamic.elf" "$TMP/$op.again.elf"
done
# Значення є тільки host тестовими векторами; арифметику обчислюють
# САМІ дві скомпільовані фізичні D5 форми та незалежний SENS.
# a, b, очікувана сума, очікувана різниця.
cat >"$TMP/vectors" <<'CASES'
7 -3 4 10
-100 55 -45 -155
0 0 0 0
1000 50 1050 950
2047 0 2047 2047
-2048 0 -2048 -2048
-1 -1 -2 0
500 -500 0 1000
CASES
encode() {
  local value="$1" target="$2"
  printf '%s\n' "$value" >"$TMP/n/source.lisp"
  # Конвертер правильно відмовляється перезаписувати фізичний файл.
  # Лише тимчасовий тестовий буфер видаляємо перед новим значенням.
  rm -f -- "$target"
  timeout 30s "$TMP/b/senschyslo" --з-укр D24 \
    "$TMP/n/source.lisp" "$target" >"$TMP/n/encode.log"
  test "$(wc -c <"$target")" -eq 5
}
native=0;oracle=0
while read -r a b sum sub;do
  encode "$a" "$TMP/n/left.sens"
  encode "$b" "$TMP/n/right.sens"
  cat "$TMP/n/left.sens" "$TMP/n/right.sens" >"$TMP/n/input.sens"
  test "$(wc -c <"$TMP/n/input.sens")" -eq 10
  for op in add7 sub7;do
    if [[ "$op" == add7 ]];then wanted="$sum";head="додати"
    else wanted="$sub";head="відняти";fi
    encode "$wanted" "$TMP/n/expected.sens"
    timeout 12s "$TMP/$op.dynamic.elf" <"$TMP/n/input.sens" \
       >"$TMP/n/result.sens" 2>"$TMP/n/exec.err"
    test ! -s "$TMP/n/exec.err"
    cmp "$TMP/n/expected.sens" "$TMP/n/result.sens"
    test "$(wc -c <"$TMP/n/result.sens")" -eq 5
    native=$((native+1))
    if [[ "$ORACLE_MODE" == full ]];then
      printf '(%s %s %s)\n' "$head" "$a" "$b" >"$TMP/n/oracle.lisp"
      timeout 90s "$ORACLE" "$TMP/n/oracle.lisp" \
        >"$TMP/n/oracle.out" 2>"$TMP/n/oracle.err"
      test ! -s "$TMP/n/oracle.err"
      printf '%s\n' "$wanted" >"$TMP/n/wanted"
      cmp "$TMP/n/oracle.out" "$TMP/n/wanted"
      oracle=$((oracle+1))
    fi
  done
done <"$TMP/vectors"
test "$native" -eq 16
if [[ "$ORACLE_MODE" == full ]];then
  test "$oracle" -eq 16
  verdict=16
else
  test "$oracle" -eq 0
  verdict=NOT-CHECKED
fi
# Фрагментований stdin з 10 окремих write виконує той самий ELF.
encode 7 "$TMP/n/left.sens"
encode -3 "$TMP/n/right.sens"
cat "$TMP/n/left.sens" "$TMP/n/right.sens" >"$TMP/n/input.sens"
python3 - "$TMP/n/input.sens" <<'PY' | timeout 8s "$TMP/add7.dynamic.elf" >"$TMP/n/fragment.out"
import sys,os,time
from pathlib import Path
for byte in Path(sys.argv[1]).read_bytes():
    os.write(1,bytes([byte]))
    time.sleep(0.01)
PY
encode 4 "$TMP/n/expected.sens"
cmp "$TMP/n/expected.sens" "$TMP/n/fragment.out"
reject=0
reject_stdin() {
  local label="$1" path="$2" rc=0
  timeout 10s "$TMP/add7.dynamic.elf" <"$path" \
    >"$TMP/n/$label.out" 2>"$TMP/n/$label.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/n/$label.out" && test ! -s "$TMP/n/$label.err"
  reject=$((reject+1))
}
: >"$TMP/n/empty.sens"
head -c5 "$TMP/n/input.sens" >"$TMP/n/one-operand.sens"
head -c9 "$TMP/n/input.sens" >"$TMP/n/short.sens"
cp "$TMP/n/input.sens" "$TMP/n/trailing.sens"
printf '\000' >>"$TMP/n/trailing.sens"
cp "$TMP/n/input.sens" "$TMP/n/bad-first.sens"
cp "$TMP/n/input.sens" "$TMP/n/bad-second.sens"
cp "$TMP/n/input.sens" "$TMP/n/bad-terminal.sens"
python3 - "$TMP/n" <<'PY'
import sys
from pathlib import Path
d=Path(sys.argv[1])
p=d/'bad-first.sens';x=bytearray(p.read_bytes());x[0]=162;p.write_bytes(x)
p=d/'bad-second.sens';x=bytearray(p.read_bytes());x[5]=255;p.write_bytes(x)
p=d/'bad-terminal.sens';x=bytearray(p.read_bytes());x[9]-=2;p.write_bytes(x)
PY
reject_stdin empty "$TMP/n/empty.sens"
reject_stdin single "$TMP/n/one-operand.sens"
reject_stdin short "$TMP/n/short.sens"
reject_stdin trailing "$TMP/n/trailing.sens"
reject_stdin trit-first "$TMP/n/bad-first.sens"
reject_stdin trit-second "$TMP/n/bad-second.sens"
reject_stdin terminal "$TMP/n/bad-terminal.sens"
test "$reject" -eq 7
negative_elf=0
reject_source() {
  local label="$1" source="$2" rc=0
  local target="$TMP/n/reject-$label.elf"
  timeout 30s "$TMP/b/sensdvaparamstdinelf" --два-фізичні-D24-stdin \
    "$source" "$target" >"$TMP/n/$label.src.out" \
    2>"$TMP/n/$label.src.err" || rc=$?
  test "$rc" -eq 2 && test ! -e "$target"
  test ! -s "$TMP/n/$label.src.out"
  grep -Fq 'ДВА-D24-STDIN-ELF-ВІДМОВА:' "$TMP/n/$label.src.err"
  negative_elf=$((negative_elf+1))
}
cp "$TMP/add7.static.elf" "$TMP/n/bad-geometry.elf"
python3 - "$TMP/n/bad-geometry.elf" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);d=bytearray(p.read_bytes());d[0]=0;p.write_bytes(d)
PY
reject_source bad-geometry "$TMP/n/bad-geometry.elf"
reject_source already-converted "$TMP/add7.dynamic.elf"
reject_source missing "$TMP/n/absent.elf"
cp "$TMP/add7.static.elf" "$TMP/n/lisp-projection.lisp"
reject_source lisp-projection "$TMP/n/lisp-projection.lisp"
# Existing target і dangling symlink не можна затерти.
cp "$TMP/add7.dynamic.elf" "$TMP/n/occupied.elf"
rc=0
timeout 30s "$TMP/b/sensdvaparamstdinelf" --два-фізичні-D24-stdin \
  "$TMP/add7.static.elf" "$TMP/n/occupied.elf" \
  >"$TMP/n/occupied.out" 2>"$TMP/n/occupied.err" || rc=$?
test "$rc" -eq 2
cmp "$TMP/add7.dynamic.elf" "$TMP/n/occupied.elf"
ln -s "$TMP/n/not-created.elf" "$TMP/n/dangling.elf"
rc=0
timeout 30s "$TMP/b/sensdvaparamstdinelf" --два-фізичні-D24-stdin \
  "$TMP/add7.static.elf" "$TMP/n/dangling.elf" \
  >"$TMP/n/dangling.out" 2>"$TMP/n/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/n/dangling.elf"
test ! -e "$TMP/n/not-created.elf"
timeout 10s "$TMP/add7.dynamic.elf" <"$TMP/n/input.sens" >"$TMP/n/recovery"
cmp "$TMP/n/recovery" "$TMP/n/expected.sens"
echo "ДВА-D24-STDIN-PASS native=$native oracle=$verdict asm=658 repeat=2 fragment=1 negative=$reject rejected-ELF=$negative_elf no-clobber=2 recovery=1 energy=NOT_MEASURED"
