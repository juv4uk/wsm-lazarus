#!/usr/bin/env bash
# G6.162 — один нативний ELF з фізичним D12 або D24 результатом під час виконання.
# Закони/підвищення ширини — pinned SENS; host-скрипт лише звіряє байти.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout readelf cmp grep mktemp python3 sha256sum wc; do
  command -v "$exe" >/dev/null || { echo "АДАПТИВНЕ-ADD-БЛОК: немає $exe" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 60s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'АДАПТИВНЕ-ADD-БЛОК: незалежний SENS oracle відсутній' >&2; exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$? file
  if ((rc)); then
    echo "АДАПТИВНЕ-ADD-ПРОВАЛ rc=$rc" >&2
    for file in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 40 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units-add" "$TMP/units-ir" "$TMP/units-frame" \
  "$TMP/units-cli" "$TMP/units-num" "$TMP/anchors" "$TMP/frames"
for row in \
  'scripts/test-elfd12add.pas test-elfd12add units-add' \
  'scripts/test-irwideaddreg.pas test-irwideaddreg units-ir' \
  'scripts/test-elfd12potik.pas test-elfd12potik units-frame' \
  'src/sensd12addpotikadaptive.lpr sensd12addpotikadaptive units-cli' \
  'src/senschyslo.lpr senschyslo units-num'; do
  read -r source name units <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd12add" "$TMP/anchors" \
  >"$TMP/add.log" 2>"$TMP/add.err"
timeout 30s "$TMP/bin/test-irwideaddreg" "$TMP/anchors" \
  >"$TMP/ir.log" 2>"$TMP/ir.err"
grep -Fq 'Д5-РЕЄСТРИ-СВІДКИ-ГАРАЗД physical=9 identical=9 negative=15' "$TMP/ir.log"
timeout 30s "$TMP/bin/test-elfd12potik" "$TMP/frames" \
  >"$TMP/valid.tsv" 2>"$TMP/frames.err"
test "$(wc -l < "$TMP/valid.tsv")" -eq 13
MODE=--зібрати-адаптивне-D5-додавання
ELF="$TMP/додати-D12-D24.elf"
timeout 50s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/anchors/01.sens" "$ELF" \
  >"$TMP/build.out" 2>"$TMP/compiler.err"
test -x "$ELF"
grep -Fq 'stdout=T5M-D12-or-D24' "$TMP/build.out"
readelf -h "$ELF" >"$TMP/header"
readelf -l "$ELF" >"$TMP/segments"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments"
python3 - "$ELF" <<'PY'
import struct,sys
from pathlib import Path
data=Path(sys.argv[1]).read_bytes()
assert data[:4]==b'\x7fELF'
assert struct.unpack_from('<Q',data,96)[0]==len(data)
assert struct.unpack_from('<Q',data,104)[0]==len(data)
assert b'\x44\x89\xc0\x44\x01\xc8\x89\xc3' in data, 'немає нативного ADD'
assert b'\x81\xe3\xff\xff\xff\x00' in data, 'немає exact D24 fast path'
assert b'\x48\x83\xf8\x05\x0f\x85' in data, 'немає write(5) перевірки'
PY
timeout 50s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/anchors/02.sens" "$TMP/rebuilt.elf" >"$TMP/rebuilt.out"
cmp "$ELF" "$TMP/rebuilt.elf"
sha256sum "$ELF" >"$TMP/elf.sha"
small=0; wide=0; oracle=0
verify_case() {
  local label="$1" left="$2" right="$3" width="$4" expected="$5" attempt
  for attempt in 1 2; do
    timeout 6s "$ELF" <"$TMP/frames/$label.frame" \
      >"$TMP/$label.$attempt.actual.sens" 2>"$TMP/$label.$attempt.err"
    test ! -s "$TMP/$label.$attempt.err"
    cmp "$expected" "$TMP/$label.$attempt.actual.sens"
    if [[ "$width" == 12 ]]; then
      test "$(wc -c <"$TMP/$label.$attempt.actual.sens")" -eq 3
    else
      test "$(wc -c <"$TMP/$label.$attempt.actual.sens")" -eq 5
    fi
  done
  if [[ -n "$ORACLE" ]]; then
    printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    timeout 12s "$TMP/bin/senschyslo" --в-укр D"$width" \
      "$TMP/$label.1.actual.sens" >"$TMP/$label.ukr"
    cmp "$TMP/$label.oracle" "$TMP/$label.ukr"
    oracle=$((oracle+1))
  fi
}
while IFS=$'\t' read -r label left right; do
  test -n "$label"
  verify_case "$label" "$left" "$right" 12 "$TMP/frames/$label-expected.sens"
  small=$((small+1))
done <"$TMP/valid.tsv"
for spec in 'overflow-up:2047:1:2048' 'overflow-down:-2048:-1:-2049' \
  'overflow-wide:2047:2047:4094'; do
  IFS=: read -r label left right result <<<"$spec"
  printf '%s\n' "$result" >"$TMP/$label.result.lisp"
  timeout 12s "$TMP/bin/senschyslo" --з-укр D24 \
    "$TMP/$label.result.lisp" "$TMP/$label.expected.sens" \
    >"$TMP/$label.mint.out" 2>"$TMP/$label.mint.err"
  verify_case "$label" "$left" "$right" 24 "$TMP/$label.expected.sens"
  wide=$((wide+1))
done
test "$small" -eq 13 && test "$wide" -eq 3
if [[ -n "$ORACLE" ]]; then test "$oracle" -eq 16; fi
neg=0
for bad in empty short1 short5 extra invalid243 badfirst badsecond \
  badthird badlast newline projection d1; do
  rc=0
  timeout 6s "$ELF" <"$TMP/frames/$bad.frame" \
    >"$TMP/$bad.native.out" 2>"$TMP/$bad.native.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$bad.native.out"
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/$bad.native.err"
  neg=$((neg+1))
done
test "$neg" -eq 12
anchor_bad=0
for bad in '01-l.sens' '01-r.sens'; do
  rc=0
  timeout 50s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
    "$TMP/anchors/$bad" "$TMP/failed-$anchor_bad.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
  test ! -e "$TMP/failed-$anchor_bad.elf"
  grep -Fq 'АДАПТИВНЕ-D5-ADD-ВІДМОВА:' "$TMP/reject.err"
  anchor_bad=$((anchor_bad+1))
done
printf '\377' >"$TMP/bad.sens"
: >"$TMP/empty.sens"
cp "$TMP/anchors/01.sens" "$TMP/not-binary.lisp"
for bad in bad.sens empty.sens not-binary.lisp; do
  rc=0
  timeout 50s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
    "$TMP/$bad" "$TMP/rejected-$anchor_bad.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
  test ! -e "$TMP/rejected-$anchor_bad.elf"
  anchor_bad=$((anchor_bad+1))
done
rc=0
timeout 50s "$TMP/bin/sensd12addpotikadaptive" "$MODE" \
  "$TMP/anchors/03.sens" "$ELF" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
(cd "$TMP" && sha256sum -c elf.sha) >"$TMP/hash.out" 2>"$TMP/hash.err" || {
  # sha256sum записаний абсолютним шляхом і не повинен підміняти ELF.
  test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$(cut -d' ' -f1 <"$TMP/elf.sha")"
}
timeout 6s "$ELF" <"$TMP/frames/01.frame" >"$TMP/recovery.sens"
cmp "$TMP/frames/01-expected.sens" "$TMP/recovery.sens"
echo "АДАПТИВНЕ-ADD-ГОТОВО d12=$small d24=$wide runs=$((2*(small+wide)+1)) oracle=$oracle negatives=$neg anchors=$anchor_bad no-clobber=yes energy=NOT-MEASURED"
