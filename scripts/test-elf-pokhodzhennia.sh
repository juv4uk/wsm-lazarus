#!/usr/bin/env bash
# G6.158 — повторне джерело -> машинні байти; тільки pinned WideIR.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for tool in fpc git timeout cmp readelf grep mktemp python3 head seq cp; do
  command -v "$tool" >/dev/null
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 15 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/sources"
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Fq '0 unfreed memory blocks' "$1"
  fi
}
for spec in 'src/senswidefrontelf.lpr senswidefrontelf' \
            'scripts/test-irwidefront.pas test-irwidefront'; do
  read -r source binary <<< "$spec"
  timeout 180s "$(printenv FPC || echo fpc)" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build.log" 2>&1 || {
      cat "$TMP/$binary.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwidefront" "$TMP/sources" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixture.log"
check_heap "$TMP/fixture.err"
COMPILE=--скомпілювати-фізичну-форму
VERIFY=--звірити-походження
PASS=0
for n in $(seq -w 1 16); do
  source="$TMP/sources/$n.sens"
  elf="$TMP/$n.elf"
  test -s "$source"
  cp "$source" "$TMP/$n.original"
  timeout 20s "$TMP/bin/senswidefrontelf" "$COMPILE" "$source" "$elf" \
    >"$TMP/$n.compile.log" 2>"$TMP/$n.compile.err"
  check_heap "$TMP/$n.compile.err"
  test -x "$elf"
  timeout 20s "$TMP/bin/senswidefrontelf" "$VERIFY" "$source" "$elf" \
    >"$TMP/$n.verify.log" 2>"$TMP/$n.verify.err"
  check_heap "$TMP/$n.verify.err"
  grep -Fq 'ЕЛЬФ-ПОХОДЖЕННЯ-ГАРАЗД:' "$TMP/$n.verify.log"
  timeout 10s "$elf" >"$TMP/$n.actual.sens" 2>"$TMP/$n.exec.err"
  test ! -s "$TMP/$n.exec.err"
  cmp "$TMP/sources/$n.expected.sens" "$TMP/$n.actual.sens"
  cmp "$source" "$TMP/$n.original"
  readelf -h "$elf" >"$TMP/$n.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$n.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$n.header"
  PASS=$((PASS+1))
done
test "$PASS" -eq 16
python3 - "$TMP/01.elf" "$TMP/corrupt.elf" <<'PY'
from pathlib import Path
import sys
b=bytearray(Path(sys.argv[1]).read_bytes())
assert len(b)>120
b[-1]^=1
Path(sys.argv[2]).write_bytes(b)
PY
head -c 119 "$TMP/01.elf" >"$TMP/truncated.elf"
cp "$TMP/01.elf" "$TMP/01.original.elf"
NEG=0
reject() {
  local name="$1"
  shift
  local rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" \
    >"$TMP/rejected.out" 2>"$TMP/rejected.err" || rc=$?
  if [[ "$rc" -ne 2 || -s "$TMP/rejected.out" ]]; then
    echo "ПОХОДЖЕННЯ-ПРОВАЛ: неправомірний результат $name rc=$rc" >&2
    exit 1
  fi
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/rejected.err"
  check_heap "$TMP/rejected.err"
  NEG=$((NEG+1))
}
reject чужий-вхід "$VERIFY" "$TMP/sources/03.sens" "$TMP/01.elf"
reject зіпсовані-байти "$VERIFY" "$TMP/sources/01.sens" "$TMP/corrupt.elf"
reject обрізаний-elf "$VERIFY" "$TMP/sources/01.sens" "$TMP/truncated.elf"
reject текст-замість-машини "$VERIFY" "$TMP/sources/01.sens" "$TMP/sources/fake.lisp"
reject текст-замість-джерела "$VERIFY" "$TMP/sources/fake.lisp" "$TMP/01.elf"
reject неканонічне-джерело "$VERIFY" "$TMP/sources/bad-t5m.sens" "$TMP/01.elf"
reject відсутній-elf "$VERIFY" "$TMP/sources/01.sens" "$TMP/nonexistent.elf"
reject відсутнє-джерело "$VERIFY" "$TMP/missing.sens" "$TMP/01.elf"
reject невідомий-режим --вигаданий "$TMP/sources/01.sens" "$TMP/01.elf"
test "$NEG" -eq 9
cmp "$TMP/01.elf" "$TMP/01.original.elf" # Верифікатор не змінює готову машину.
cmp "$TMP/sources/01.sens" "$TMP/01.original"
echo "G6.158-ПОХОДЖЕННЯ-ГАРАЗД fpc=checked physical=16 ELF64=16 executed=16 exact=16 negative=$NEG oracle=NOT-CHECKED energy=NOT-MEASURED"
