#!/usr/bin/env bash
# G6.172 — тільки FPC + машинний ELF; жодного Rust, Zig, Go або network oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for exe in python3 git fpc timeout cmp readelf mktemp grep; do
  command -v "$exe" >/dev/null || { echo "ЕНЕРГО-CI-ВІДМОВА: немає $exe" >&2; exit 127; }
done
test "$(uname -s)" = Linux && test "$(uname -m)" = x86_64
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh

python3 -m py_compile scripts/test-enerhooshchadnyi-ci.py
timeout 20s python3 scripts/test-enerhooshchadnyi-ci.py --selftest

TMP="$(mktemp -d)"
trap 'code=$?; if ((code));then
  echo "ЕНЕРГО-CI-ЕЛЬФ-ВІДМОВА code=$code line=$LINENO" >&2
  for f in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 22 "$f" >&2; fi
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/u" "$TMP/bin" "$TMP/fixtures"
for row in 'scripts/test-irwidensd.pas:test-irwidensd' \
           'src/senswidefrontelf.lpr:senswidefrontelf'; do
  IFS=: read -r source binary <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    "-Fu$ROOT/src" "-FU$TMP/u" "-FE$TMP/bin" "-o$binary" \
    "$ROOT/$source" > "$TMP/$binary.build.log" 2>&1 || {
      cat "$TMP/$binary.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 60s "$TMP/bin/test-irwidensd" "$TMP/fixtures" > "$TMP/fixtures.log"
grep -Fq 'G6.105-NSD-FIXTURES-OK cases=14' "$TMP/fixtures.log"

native=0
for tag in 01 02; do
  timeout 40s "$TMP/bin/senswidefrontelf" \
    --скомпілювати-фізичну-форму "$TMP/fixtures/$tag.sens" \
    "$TMP/$tag.elf" > "$TMP/$tag.compile.log" 2>"$TMP/$tag.compile.err"
  test ! -s "$TMP/$tag.compile.err"
  test -x "$TMP/$tag.elf"
  timeout 8s readelf -h "$TMP/$tag.elf" > "$TMP/$tag.header"
  grep -Eq 'Class:[[:space:]]+ELF64' "$TMP/$tag.header"
  grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64' "$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
  timeout 8s "$TMP/$tag.elf" > "$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
  test ! -s "$TMP/$tag.machine.err"
  cmp "$TMP/$tag.actual.sens" "$TMP/fixtures/$tag.expected.sens"
  native=$((native+1))
done
test "$native" -eq 2

negative=0
for tag in bad-t5m two-roots other-d7; do
  rc=0
  timeout 40s "$TMP/bin/senswidefrontelf" \
    --скомпілювати-фізичну-форму "$TMP/fixtures/$tag.sens" \
    "$TMP/rejected-$tag.elf" > "$TMP/$tag.out" 2> "$TMP/$tag.err" || rc=$?
  test "$rc" -eq 2
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА' "$TMP/$tag.err"
  test ! -e "$TMP/rejected-$tag.elf"
  test ! -s "$TMP/$tag.out"
  negative=$((negative+1))
done
test "$negative" -eq 3

# Повторний запуск повинен залишатися детермінованим та без перезапису.
rc=0
timeout 40s "$TMP/bin/senswidefrontelf" \
  --скомпілювати-фізичну-форму "$TMP/fixtures/01.sens" \
  "$TMP/01.elf" > "$TMP/no-clobber.out" 2> "$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
timeout 40s "$TMP/bin/senswidefrontelf" \
  --скомпілювати-фізичну-форму "$TMP/fixtures/01.sens" \
  "$TMP/repeat.elf" > "$TMP/repeat.log"
cmp "$TMP/01.elf" "$TMP/repeat.elf"

echo "ЕНЕРГО-CI-МАШИНА-ГАРАЗД fpc=так native=$native negatives=$negative no-clobber=так byte-repeat=так energy=NOT-MEASURED"
timeout 20s python3 scripts/test-enerhooshchadnyi-ci.py
echo "ЕНЕРГО-CI-ЕЛЬФ-ГАРАЗД fpc=так native=$native negatives=$negative no-clobber=так byte-repeat=так oracle=збережено-окремо heavy-push=0 energy=NOT-MEASURED"
