#!/usr/bin/env bash
# G6: тільки реальні FPC + canonical T5M + ELF64, PR/manual.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git cmp python3 readelf mktemp chmod grep; do
  command -v "$tool" >/dev/null || {
    echo "ЕТАПИ-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕТАПИ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
timeout 10s python3 scripts/test-wide-first-stage-profile.py --самоперевірка

TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc)); then
    echo "ЕТАПИ-ТЕСТ-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/elf" "$TMP/reference"
for spec in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'scripts/test-wide-first-stage-profile.pas test-wide-first-stage-profile'; do
  read -r file name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$file" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
      cat "$TMP/$name.build" "$TMP/$name.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.log"

timeout 600s \
  "$TMP/bin/test-wide-first-stage-profile" --етапи "$TMP/physical" "$TMP/elf" \
  >"$TMP/raw.tsv" 2>"$TMP/stage.err"
SENS_STAGE_REPORT="$TMP/result.json" timeout 15s \
  python3 scripts/test-wide-first-stage-profile.py "$TMP/raw.tsv" \
  >"$TMP/stats.log"
test -s "$TMP/result.json"
grep -Fq 'ЕТАПИ-ПРОЙДЕНО фізичних=16 повторів=3 raw=48' "$TMP/stats.log"

GOOD=0
for n in $(seq -w 1 16); do
  source="$TMP/physical/$n.sens"
  actual="$TMP/elf/$n.elf"
  reference="$TMP/reference/$n.elf"
  test -s "$actual"
  timeout 25s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$source" "$reference" >"$TMP/ref-$n.log" 2>"$TMP/ref-$n.err"
  cmp "$actual" "$reference"
  readelf -h "$actual" >"$TMP/header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  chmod 700 "$actual"
  timeout 5s "$actual" >"$TMP/$n.actual.sens" 2>"$TMP/$n.machine.err"
  test ! -s "$TMP/$n.machine.err"
  cmp "$TMP/physical/$n.expected.sens" "$TMP/$n.actual.sens"
  GOOD=$((GOOD+1))
done
test "$GOOD" -eq 16

NEG=0
for case in bad-t5m empty bad-zero-arity two-roots; do
  rc=0
  timeout 25s "$TMP/bin/test-wide-first-stage-profile" --негатив \
    "$TMP/physical/$case.sens" >"$TMP/rejected.out" \
    2>"$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/rejected.out"
  grep -Fq 'ЕТАПИ-ПРОВАЛ:' "$TMP/rejected.err"
  NEG=$((NEG+1))
done
test "$NEG" -eq 4
# Після негативів той самий pinned профіль компілюється і виконується.
timeout 25s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
  "$TMP/physical/01.sens" "$TMP/recovered.elf" >/dev/null
cmp "$TMP/recovered.elf" "$TMP/elf/01.elf"
echo 'ЕТАПИ-МАШИНА-ГАРАЗД фізичних=16 elf=16 byte-identical=16 negative=4 recovery=так'
cat "$TMP/stats.log"
if [[ -n "${SENS_STAGE_REPORT_DEST:-}" ]]; then
  cp "$TMP/result.json" "$SENS_STAGE_REPORT_DEST"
fi
