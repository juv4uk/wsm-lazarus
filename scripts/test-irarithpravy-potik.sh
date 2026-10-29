#!/usr/bin/env bash
# G6.146 — реальний stdin → ТОЙ САМИЙ ELF64 для 36 right-nested D5.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for command_name in git fpc timeout cmp readelf python3 grep mktemp; do
  command -v "$command_name" >/dev/null || {
    echo "ПРАВИЙ-ПОТІК: потрібен $command_name" >&2; exit 127;
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ПРАВИЙ-ПОТІК: потрібен Linux x86-64' >&2; exit 127;
}
timeout 60s ./scripts/check-pin.sh
timeout 60s ./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788

TMP=$(mktemp -d)
fail() {
  local rc=$?
  echo "ПРАВИЙ-ПОТІК-ПРОВАЛ рядок=$1 rc=$rc" >&2
  for file in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$file" ]]; then
      echo "--- $file" >&2; tail -n 10 "$file" >&2
    fi
  done
  exit "$rc"
}
trap 'fail "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/sensarithpravypotik.lpr sensarithpravypotik' \
  'src/sensarithpravyelf.lpr sensarithpravyelf' \
  'scripts/test-irarithpravy.pas test-irarithpravy'; do
  read -r source executable <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build.log" 2>&1 || {
      cat "$TMP/$executable.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$executable"
done
heap_ok() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1" || {
      cat "$1" >&2; exit 1;
    }
  fi
}
timeout 120s "$TMP/bin/test-irarithpravy" "$TMP/fixtures" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fxq 'G6.141-RIGHT-D5-UNIT-OK positive=36 negative=16' \
  "$TMP/generator.log"
heap_ok "$TMP/generator.err"

PASS=0
for depth in $(seq 1 8) 16; do
  for k in 0 1 2 3; do
    tag="$depth-$k"
    source="$TMP/fixtures/$tag.sens"
    reference="$TMP/fixtures/$tag.elf"
    expected="$TMP/fixtures/$tag.expected.sens"
    test -s "$source" && test -s "$reference" && test -s "$expected"
    timeout 25s "$TMP/bin/sensarithpravypotik" --правий-потік-D5 \
      <"$source" >"$TMP/$tag.stream.elf" 2>"$TMP/$tag.stream.err"
    heap_ok "$TMP/$tag.stream.err"
    cmp "$reference" "$TMP/$tag.stream.elf"
    readelf -h "$TMP/$tag.stream.elf" >"$TMP/$tag.header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
    if readelf -l "$TMP/$tag.stream.elf" | grep -Eq 'INTERP|DYNAMIC'; then
      echo "ПРАВИЙ-ПОТІК: заборонена динамічна залежність: $tag" >&2
      exit 1
    fi
    chmod 700 "$TMP/$tag.stream.elf"
    timeout 5s "$TMP/$tag.stream.elf" \
      >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    cmp "$expected" "$TMP/$tag.actual.sens"
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
    PASS=$((PASS+1))
  done
done
test "$PASS" -eq 36

# Файловий CLI і stdin CLI — байтово ОДНАКОВІ, а не два backend.
timeout 25s "$TMP/bin/sensarithpravyelf" --правий-ланцюг-D5 \
  "$TMP/fixtures/16-2.sens" "$TMP/16-2.file.elf" \
  >"$TMP/filecli.out" 2>"$TMP/filecli.err"
heap_ok "$TMP/filecli.err"
cmp "$TMP/16-2.file.elf" "$TMP/fixtures/16-2.elf"

# Реальний фізичний pipe із фрагментами по одному байту.
python3 - "$TMP/bin/sensarithpravypotik" \
  "$TMP/fixtures/16-2.sens" "$TMP/fixtures/16-2.elf" <<'PY'
from pathlib import Path
import subprocess
import sys
binary, physical, reference = sys.argv[1:]
p = subprocess.Popen([binary, '--правий-потік-D5'],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE)
for byte in Path(physical).read_bytes():
    p.stdin.write(bytes([byte]))
    p.stdin.flush()
p.stdin.close()
image = p.stdout.read()
stderr = p.stderr.read()
rc = p.wait(timeout=30)
assert rc == 0, (rc, stderr)
assert image == Path(reference).read_bytes(), (len(image), stderr)
assert (b'unfreed memory blocks' not in stderr or
        b'0 unfreed memory blocks' in stderr), stderr
PY

# Негативи відокремлені від позитивних fixtures. Усі fail-closed,
# жоден байт ELF на stdout до завершення повного допуску T5M/WideIR.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
base=(p/'fixtures/16-2.sens').read_bytes()
(p/'empty.sens').write_bytes(b'')
(p/'badbyte.sens').write_bytes(b'\xff')
(p/'overquota.sens').write_bytes(b'0'*8193)
(p/'atquota.sens').write_bytes(b'0'*8192)
(p/'latecorrupt.sens').write_bytes(base+b'\xff')
(p/'twofiles.sens').write_bytes(base+base)
(p/'truncated.sens').write_bytes(base[:-5])
(p/'projection.lisp').write_text('(відняти 7 (додати 3 2))\n',encoding='utf-8')
(p/'leadinginvalid.sens').write_bytes(b'\xff'+base)
(p/'tailinvalid.sens').write_bytes(base+b'\xff\xff')
PY
NEG=0
reject() {
  local input="$1" rc=0
  timeout 25s "$TMP/bin/sensarithpravypotik" --правий-потік-D5 \
    <"$TMP/$input" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  if [[ "$rc" -ne 2 || -s "$TMP/reject.out" ]]; then
    echo "ПРАВИЙ-ПОТІК: частковий ELF або невірний status=$rc для $input" >&2
    cat "$TMP/reject.err" >&2
    exit 1
  fi
  test -s "$TMP/reject.err"
  heap_ok "$TMP/reject.err"
  NEG=$((NEG+1))
}
for bad in empty.sens badbyte.sens overquota.sens atquota.sens \
  latecorrupt.sens twofiles.sens truncated.sens projection.lisp \
  leadinginvalid.sens tailinvalid.sens; do
  reject "$bad"
done
test "$NEG" -eq 10

rc=0
timeout 15s "$TMP/bin/sensarithpravypotik" --неправильний-режим \
  <"$TMP/fixtures/1-0.sens" >"$TMP/wrong.out" \
  2>"$TMP/wrong.err" || rc=$?
test "$rc" -eq 64 && test ! -s "$TMP/wrong.out"
test -s "$TMP/wrong.err"

# Не залишається часткового стану — відразу після кожної відмови
# той самий фізичний вхід знову дає байтово той самий ELF.
timeout 25s "$TMP/bin/sensarithpravypotik" --правий-потік-D5 \
  <"$TMP/fixtures/16-2.sens" >"$TMP/recovered.elf" \
  2>"$TMP/recovered.err"
heap_ok "$TMP/recovered.err"
cmp "$TMP/recovered.elf" "$TMP/fixtures/16-2.elf"
echo "G6.146-RIGHT-D5-STREAM-OK physical=$PASS byte-identical=$PASS executed=$PASS negative=$NEG fragmented=1-byte recovery=yes oracle=separate-pinned-job energy=NOT-MEASURED"
