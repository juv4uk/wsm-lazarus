#!/usr/bin/env bash
# G6.144 — фізичний D5 stdin→ELF64 stdout через вже перевірений
# BuildIRArithChainELF, не окреме lowering і не таблиця законів.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git fpc timeout cmp readelf python3 grep mktemp; do
  command -v "$tool" >/dev/null || { echo "ПОТІК-Д5: бракує $tool" >&2; exit 127; }
done
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo "ПОТІК-Д5: потрібен Linux x86-64" >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788

TMP=$(mktemp -d)
failure() {
  local code=$?
  echo "ПОТІК-Д5-ПРОВАЛ рядок=$1 status=$code" >&2
  for log in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$log" ]]; then
      echo "--- $log" >&2
      tail -n 14 "$log" >&2
    fi
  done
  exit "$code"
}
trap 'failure "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/fixtures"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/sensarithchainpotik.lpr sensarithchainpotik' \
  'src/sensarithchainelf.lpr sensarithchainelf' \
  'scripts/test-irarithchain.pas test-irarithchain'; do
  read -r source name <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.log" 2>&1 || {
      cat "$TMP/$name.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done

check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1" || {
      cat "$1" >&2; exit 1;
    }
  fi
}
timeout 120s "$TMP/bin/test-irarithchain" "$TMP/fixtures" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fxq 'D5-ARITH-CHAIN-UNIT-OK positive=71 negative=24' "$TMP/fixtures.log"
check_heap "$TMP/fixtures.err"

PASS=0
for depth in $(seq 1 16) 50 100; do
  for idx in 0 1 2 3 4; do
    if (( depth <= 16 && idx == 4 )); then continue; fi
    if (( depth > 16 && idx == 0 )); then continue; fi
    if (( depth == 50 && idx == 4 )); then continue; fi
    tag="$depth-$idx"
    source="$TMP/fixtures/$tag.sens"
    reference="$TMP/fixtures/$tag.elf"
    expected="$TMP/fixtures/$tag.expected.sens"
    test -s "$source" && test -s "$reference" && test -s "$expected"
    timeout 25s "$TMP/bin/sensarithchainpotik" --ланцюг-потік-D5 \
      <"$source" >"$TMP/$tag.pipe.elf" 2>"$TMP/$tag.pipe.err"
    check_heap "$TMP/$tag.pipe.err"
    cmp "$reference" "$TMP/$tag.pipe.elf"
    timeout 25s "$TMP/bin/sensarithchainelf" --ланцюг-D5 \
      "$source" "$TMP/$tag.file.elf" \
      >"$TMP/$tag.file.out" 2>"$TMP/$tag.file.err"
    check_heap "$TMP/$tag.file.err"
    cmp "$reference" "$TMP/$tag.file.elf"
    readelf -h "$TMP/$tag.pipe.elf" >"$TMP/$tag.header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
    if readelf -l "$TMP/$tag.pipe.elf" | grep -Eq 'INTERP|DYNAMIC'; then
      echo "ПОТІК-Д5: динамічна ELF залежність $tag" >&2; exit 1
    fi
    chmod 700 "$TMP/$tag.pipe.elf"
    timeout 5s "$TMP/$tag.pipe.elf" >"$TMP/$tag.actual.sens" \
      2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    cmp "$expected" "$TMP/$tag.actual.sens"
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
    PASS=$((PASS+1))
  done
done
test "$PASS" -eq 71

# Справжній pipe 1 байт за запис, навіть для 100 рівнів:
# жодного seek, проміжних ELF або втраченої частини кадру.
python3 - "$TMP/bin/sensarithchainpotik" \
  "$TMP/fixtures/100-4.sens" "$TMP/fixtures/100-4.elf" <<'PY'
from pathlib import Path
import subprocess
import sys
binary, payload, reference = sys.argv[1:]
p = subprocess.Popen([binary,'--ланцюг-потік-D5'],stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE,stderr=subprocess.PIPE)
for byte in Path(payload).read_bytes():
    p.stdin.write(bytes([byte]))
    p.stdin.flush()
p.stdin.close()
out = p.stdout.read()
err = p.stderr.read()
rc = p.wait(timeout=30)
assert rc == 0 and out == Path(reference).read_bytes(), (rc,len(out),err)
assert b'unfreed memory blocks' not in err or b'0 unfreed memory blocks' in err,err
PY

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
base=(p/'fixtures/100-4.sens').read_bytes()
(p/'empty.sens').write_bytes(b'')
(p/'badbyte.sens').write_bytes(b'\xff')
(p/'overquota.sens').write_bytes(b'0'*8193)
(p/'atquota.sens').write_bytes(b'0'*8192)
(p/'latecorrupt.sens').write_bytes(base+b'\xff')
(p/'twofiles.sens').write_bytes(base+base)
(p/'truncated.sens').write_bytes(base[:-5])
(p/'text.lisp').write_text('(додати 2 3)\n',encoding='utf-8')
(p/'leadinginvalid.sens').write_bytes(b'\xff'+base)
(p/'tailinvalid.sens').write_bytes(base+b'\xff\xff')
PY
NEG=0
reject() {
  local name="$1" rc=0
  timeout 25s "$TMP/bin/sensarithchainpotik" --ланцюг-потік-D5 \
    <"$TMP/$name" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  if [[ "$rc" -ne 2 ]] || [[ -s "$TMP/reject.out" ]]; then
    echo "ПОТІК-Д5: немає атомарної відмови $name, rc=$rc" >&2
    cat "$TMP/reject.err" >&2
    exit 1
  fi
  grep -Fq 'ЛАНЦЮГ-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
  check_heap "$TMP/reject.err"
  NEG=$((NEG+1))
}
for bad in empty.sens badbyte.sens overquota.sens atquota.sens \
  latecorrupt.sens twofiles.sens truncated.sens text.lisp \
  leadinginvalid.sens tailinvalid.sens; do
  reject "$bad"
done
test "$NEG" -eq 10

rc=0
timeout 15s "$TMP/bin/sensarithchainpotik" --неправильний-режим \
  <"$TMP/fixtures/100-4.sens" >"$TMP/wrong.out" \
  2>"$TMP/wrong.err" || rc=$?
test "$rc" -eq 64 && test ! -s "$TMP/wrong.out"
grep -Fq 'Виклик:' "$TMP/wrong.err"

# Після помилок: незмінений CLI знову видає той самий ELF.
timeout 30s "$TMP/bin/sensarithchainpotik" --ланцюг-потік-D5 \
  <"$TMP/fixtures/100-4.sens" >"$TMP/recovered.elf" \
  2>"$TMP/recovered.err"
check_heap "$TMP/recovered.err"
cmp "$TMP/recovered.elf" "$TMP/fixtures/100-4.elf"
echo "D5-ПОТІК-ELF64-ГАРАЗД: FPC=так physical=71 byte-identical=71 executed=71 negative=10 fragmented=100 recovery=так oracle=existing-pinned-gate energy=NOT-MEASURED"
