#!/usr/bin/env bash
# G6.192 — один pinned verified WideIR для D6:010011, справжній FPC/ELF64.
# Час вимірюється для першої нової фізичної програми у постійному процесі.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'КОНТЕКСТ-Д6-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in git fpc timeout python3 mktemp grep; do
  command -v "$cmd" >/dev/null || {
    echo "КОНТЕКСТ-Д6-БЛОК: немає $cmd" >&2; exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -Fq '(010011 (ук модуль) (укр модуль)'
TMP="$(mktemp -d)"
cleanup() {
  rc=$?
  if ((rc)); then
    echo "КОНТЕКСТ-Д6-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'scripts/test-irwideabs.pas test-irwideabs' \
  'src/senswideabskontekst.lpr senswideabskontekst'; do
  read -r source binary <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>"$TMP/$binary.err" || {
      cat "$TMP/$binary.build" "$TMP/$binary.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwideabs" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'G6.93-ABS-FIXTURES-OK cases=14' "$TMP/generator.out"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 14
test "$(wc -c < "$TMP/physical/08.expected.sens")" -eq 5
REPORT="${SENS_ABS_CONTEXT_REPORT:-$TMP/report.json}"
timeout 1100s python3 scripts/test-abs-context-compiler.py \
  "$TMP/bin/senswideabskontekst" "$TMP/physical" "$REPORT"
test -s "$REPORT"
python3 - "$REPORT" <<'PY'
import json,sys
from pathlib import Path
x=json.loads(Path(sys.argv[1]).read_text())
assert x["byte_identical_elf"] == x["executed_elf"] == 14
assert x["samples_per_mode"] == 84
assert len(x["raw"]["old"]) == len(x["raw"]["new"]) == 84
assert x["negative_fixtures"] == 15
assert x["recoverable_negative"] == 14
assert x["no_cross_program_cache"] is True
assert x["oracle"].startswith("NOT_VERIFIED")
assert x["energy"] == "NOT_MEASURED"
print("КОНТЕКСТ-Д6-МОДУЛЬ-ЗВІТ-ПЕРЕВІРЕНО")
PY
