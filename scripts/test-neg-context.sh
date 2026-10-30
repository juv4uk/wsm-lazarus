#!/usr/bin/env bash
# G6.193 — FPC-only PR/manual; жодного нового x86 emitter чи кешу.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout python3 mktemp grep cmp readelf chmod; do
  command -v "$tool" >/dev/null || { echo "НЕГ-КОНТЕКСТ-БЛОК: немає $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -Fq '(010010 (ук змінити-знак) (укр змінити-знак)'

TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc)); then
    echo "НЕГ-КОНТЕКСТ-ПРОВАЛ rc=$rc рядок=${BASH_LINENO[0]:-unknown}" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.out; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 32 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/elf"
for row in \
  'scripts/test-irwideneg.pas test-irwideneg' \
  'scripts/test-neg-context.pas test-neg-context' \
  'src/senswidenegelf.lpr senswidenegelf'; do
  read -r src bin <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" \
    "$ROOT/$src" >"$TMP/$bin.build" 2>"$TMP/$bin.err" || {
      cat "$TMP/$bin.build" "$TMP/$bin.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$bin"
done
timeout 30s "$TMP/bin/test-irwideneg" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'G6.133-NEG-FIXTURES-OK cases=14' "$TMP/fixtures.out"
timeout 450s "$TMP/bin/test-neg-context" "$TMP/physical" "$TMP/elf" \
  >"$TMP/test.out" 2>"$TMP/test.err" || {
    cat "$TMP/test.err" >&2; exit 1;
  }
grep -Fq 'NEG-КОНТЕКСТ-ГАРАЗД' "$TMP/test.out"
SUCCESS=0
for n in $(seq -w 1 14); do
  old="$TMP/elf/$n.old.elf"
  new="$TMP/elf/$n.new.elf"
  test -s "$old" && test -s "$new"
  cmp "$old" "$new"
  readelf -h "$new" >"$TMP/$n.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$n.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$n.header"
  chmod 700 "$new"
  timeout 5s "$new" >"$TMP/$n.actual.sens" 2>"$TMP/$n.machine.err"
  test ! -s "$TMP/$n.machine.err"
  cmp "$TMP/physical/$n.expected.sens" "$TMP/$n.actual.sens"
  SUCCESS=$((SUCCESS+1))
done
test "$SUCCESS" -eq 14
test "$(wc -c < "$TMP/physical/08.expected.sens")" -eq 5
test "$(wc -c < "$TMP/08.actual.sens")" -eq 5

# Чинний окремий compiler CLI має залишитися побайтово тотожним.
timeout 30s "$TMP/bin/senswidenegelf" \
  --скомпілювати-D6-змінити-знак-D12 \
  "$TMP/physical/08.sens" "$TMP/reference.elf" >"$TMP/reference.out" \
  2>"$TMP/reference.err"
cmp "$TMP/reference.elf" "$TMP/elf/08.new.elf"

# Незалежний pinned SENS oracle запускає вже наявний тест, якщо
# зовнішній SENS_ORACLE_BIN переданий і pinned; інакше не вигадуємо proof.
ORACLE_STATUS=NOT_VERIFIED
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  ORACLE_STATUS=VERIFIED_BY_EXISTING_NEG_TEST
fi
timeout 540s bash scripts/test-irwideneg.sh >"$TMP/legacy.out" \
  2>"$TMP/legacy.err" || { cat "$TMP/legacy.err" >&2; exit 1; }
grep -Fq 'ШИРОКИЙ-Д6-ЗНАК-ГАРАЗД ELF=14 негативів=20' "$TMP/legacy.out"
echo "НЕГ-КОНТЕКСТ-МАШИНА-ГАРАЗД ELF=14 byte-parity=14 negatives=17+20 recovery=yes oracle=$ORACLE_STATUS energy=NOT_MEASURED"
