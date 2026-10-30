#!/usr/bin/env bash
# G6.161 — один ELF64, сім різних фізичних D24 stdin із pinned SENS oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for t in fpc timeout as objcopy python3 readelf cmp mktemp git grep wc stat;do
  command -v "$t" >/dev/null || { echo "НЕМАЄ: $t" >&2;exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
ORACLE="$(printenv SENS_ORACLE_BIN || true)"
test -n "$ORACLE" && test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
cleanup() {
  local code=$?
  if ((code));then
    echo "ФІЗИЧНИЙ-STDIN-ПРОВАЛ code=$code" >&2
    for f in "$TMP"/*.build "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "-- $f" >&2;tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/b" "$TMP/u" "$TMP/p"
timeout 30s as -o "$TMP/stub.o" scripts/par-t5mstdin-x86-64.S
timeout 30s objcopy -j .text -O binary "$TMP/stub.o" "$TMP/stub.bin"
python3 - "$ROOT/src/wsm.bodyt5mstdin.pas" "$TMP/stub.bin" <<'PY'
from pathlib import Path
import sys,re
source=Path(sys.argv[1]).read_text()
data=source.split("StubHex=",1)[1].split(";\n  StdoutStart:",1)[0]
expected=bytes.fromhex("".join(re.findall(r"'([0-9a-f]+)'",data)))
actual=Path(sys.argv[2]).read_bytes()
assert len(expected)==635, len(expected)
assert expected==actual, "GNU-as stub differs from Pascal embedded machine code"
assert expected[0x26a:0x26f]==b'\xe9\x00\x00\x00\x00'
print("T5M-MACHINE-ASM-OK bytes=635")
PY
for spec in \
  "src/sensparfileelf.lpr:sensparfileelf" \
  "src/sensparstdinizeelf.lpr:sensparstdinizeelf" \
  "scripts/test-parfile-fixtures.pas:test-parfile-fixtures";do
  IFS=: read -r source exe <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build" 2>&1 || {
      cat "$TMP/$exe.build" >&2;exit 1;
    }
  test -x "$TMP/b/$exe"
done
timeout 60s "$TMP/b/test-parfile-fixtures" "$ROOT" "$TMP/p" \
 >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
test "$(wc -l <"$TMP/cases.tsv")" -eq 7
test ! -s "$TMP/fixtures.err"
MODE=--скомпілювати-фізичну-пару
timeout 60s "$TMP/b/sensparfileelf" "$MODE" \
 "$TMP/p/тіло-а.sens" "$TMP/p/імя-а.sens" \
 "$TMP/p/тіло-б.sens" "$TMP/p/імя-б.sens" \
 "$TMP/p/параметр.sens" "$TMP/p/arg-0.sens" "$TMP/static.elf" \
 >"$TMP/static.log" 2>"$TMP/static.err"
test ! -s "$TMP/static.err"
timeout 60s "$TMP/b/sensparstdinizeelf" --фізичний-D24-stdin \
 "$TMP/static.elf" "$TMP/dynamic.elf" >"$TMP/postpass.log" \
 2>"$TMP/postpass.err"
test ! -s "$TMP/postpass.err"
grep -Fq 'runtime=yes result=D24-T5M' "$TMP/postpass.log"
test "$(stat -c %a "$TMP/dynamic.elf")" = 700
timeout 10s readelf -h "$TMP/dynamic.elf" >"$TMP/elf.header"
grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/elf.header"
if readelf -l "$TMP/dynamic.elf" | grep -Eq 'INTERP|DYNAMIC';then
  echo 'НЕПРИПУСТИМИЙ-DYNAMIC-LOADER' >&2;exit 1
fi
timeout 60s "$TMP/b/sensparstdinizeelf" --фізичний-D24-stdin \
 "$TMP/static.elf" "$TMP/repeat.elf" >"$TMP/repeat.log"
cmp "$TMP/dynamic.elf" "$TMP/repeat.elf"
cat >"$TMP/oracle-base.lisp" <<'LISP'
(визначити парне
  (функція (величина)
    (за-умовою
      ((менше? величина 1) 1)
      (так (непарне (відняти величина 1))))))
(визначити непарне
  (функція (величина)
    (за-умовою
      ((менше? величина 1) 0)
      (так (парне (відняти величина 1))))))
LISP
count=0;oracle=0
while IFS=$'\t' read -r n expected;do
  test -n "$n"
  timeout 8s "$TMP/dynamic.elf" <"$TMP/p/arg-$n.sens" \
    >"$TMP/$n.out.sens" 2>"$TMP/$n.exec.err"
  test ! -s "$TMP/$n.exec.err"
  test "$(wc -c <"$TMP/$n.out.sens")" -eq 5
  cmp "$TMP/$n.out.sens" "$TMP/p/expected-$n.sens"
  cp "$TMP/oracle-base.lisp" "$TMP/$n.oracle.lisp"
  printf '(парне %s)\n' "$n" >>"$TMP/$n.oracle.lisp"
  timeout 90s "$ORACLE" "$TMP/$n.oracle.lisp" \
    >"$TMP/$n.oracle.out" 2>"$TMP/$n.oracle.err"
  test ! -s "$TMP/$n.oracle.err"
  printf '%s\n' "$expected" >"$TMP/$n.oracle.want"
  cmp "$TMP/$n.oracle.out" "$TMP/$n.oracle.want"
  count=$((count+1));oracle=$((oracle+1))
done <"$TMP/cases.tsv"
test "$count" -eq 7 && test "$oracle" -eq 7
python3 - "$TMP/p/arg-8.sens" <<'PY' | timeout 8s "$TMP/dynamic.elf" >"$TMP/fragment.out.sens"
import sys,os,time
from pathlib import Path
for byte in Path(sys.argv[1]).read_bytes():
    os.write(1,bytes([byte]))
    time.sleep(0.01)
PY
cmp "$TMP/fragment.out.sens" "$TMP/p/expected-8.sens"
bad=0
reject_stdin() {
  local label="$1" path="$2" rc=0
  timeout 8s "$TMP/dynamic.elf" <"$path" \
    >"$TMP/$label.stdout" 2>"$TMP/$label.stderr" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.stdout"
  test ! -s "$TMP/$label.stderr"
  bad=$((bad+1))
}
: >"$TMP/empty.sens"
head -c4 "$TMP/p/arg-2.sens" >"$TMP/short.sens"
cp "$TMP/p/arg-2.sens" "$TMP/extra.sens"
printf '\000' >>"$TMP/extra.sens"
cp "$TMP/p/arg-2.sens" "$TMP/terminal-bad.sens"
python3 - "$TMP/terminal-bad.sens" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);d=bytearray(p.read_bytes());d[4]-=2;p.write_bytes(d)
PY
reject_stdin empty "$TMP/empty.sens"
reject_stdin short "$TMP/short.sens"
reject_stdin trailing "$TMP/extra.sens"
reject_stdin corrupt "$TMP/p/bad-t5m.sens"
reject_stdin terminal "$TMP/terminal-bad.sens"
cp "$TMP/p/arg-2.sens" "$TMP/trit2.sens"
python3 - "$TMP/trit2.sens" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);d=bytearray(p.read_bytes());d[0]=162;p.write_bytes(d)
PY
reject_stdin trit2 "$TMP/trit2.sens"
test "$bad" -eq 6
reject_source() {
  local label="$1" source="$2" rc=0
  local output="$TMP/rejected-$label.elf"
  timeout 30s "$TMP/b/sensparstdinizeelf" --фізичний-D24-stdin \
    "$source" "$output" >"$TMP/rejected-$label.out" \
    2>"$TMP/rejected-$label.err" || rc=$?
  test "$rc" -eq 2 && test ! -e "$output"
  test ! -s "$TMP/rejected-$label.out"
  grep -Fq 'ФІЗИЧНИЙ-D24-STDIN-ELF-ВІДМОВА:' "$TMP/rejected-$label.err"
}
cp "$TMP/static.elf" "$TMP/bad-geometry.elf"
python3 - "$TMP/bad-geometry.elf" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);b=bytearray(p.read_bytes());b[0]=0;p.write_bytes(b)
PY
reject_source geometry "$TMP/bad-geometry.elf"
reject_source second-postpass "$TMP/dynamic.elf"
reject_source missing "$TMP/absent.elf"
cp "$TMP/static.elf" "$TMP/projection.lisp"
reject_source projection "$TMP/projection.lisp"
cp "$TMP/dynamic.elf" "$TMP/occupied.elf"
rc=0
timeout 30s "$TMP/b/sensparstdinizeelf" --фізичний-D24-stdin \
 "$TMP/static.elf" "$TMP/occupied.elf" >"$TMP/occupied.out" \
 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/dynamic.elf" "$TMP/occupied.elf"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 30s "$TMP/b/sensparstdinizeelf" --фізичний-D24-stdin \
 "$TMP/static.elf" "$TMP/dangling.elf" >"$TMP/dangling.out" \
 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/nonexistent.elf"
timeout 8s "$TMP/dynamic.elf" <"$TMP/p/arg-5.sens" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/p/expected-5.sens"
echo "ФІЗИЧНИЙ-D24-STDIN-PASS machine=$count oracle=$oracle assembly=635 byte-repeat=1 fragmented=1 negative-stdin=$bad reject-source=4 no-clobber=2 recovery=1 energy=NOT_MEASURED"
