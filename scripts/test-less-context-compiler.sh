#!/usr/bin/env bash
# G6.191 — тільки FPC/D5:11010 «менше?» 18 нових фізичних форм.
# Старий маршрут є byte-exact oracle для machine image, незалежний
# pinned SENS — окремий PR job; speedup без повторного output-cache.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || exit 127
for tool in fpc git python3 timeout mktemp grep;do
  command -v "$tool" >/dev/null || { echo "МЕНШЕ-КОНТЕКСТ-БЛОК $tool" >&2;exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
grep -Fq '(11010 (ук менше?) (укр менше?)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
cleanup() {
  rc=$?
  if ((rc));then
    echo "МЕНШЕ-КОНТЕКСТ-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for line in \
  'scripts/test-irwideless.pas test-irwideless' \
  'src/senswidelesskontekst.lpr senswidelesskontekst';do
  read -r path binary <<<"$line"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$path" >"$TMP/$binary.build" 2>"$TMP/$binary.err" || {
      cat "$TMP/$binary.build" "$TMP/$binary.err" >&2;exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 40s "$TMP/bin/test-irwideless" "$TMP/physical" \
  >"$TMP/fixture.out" 2>"$TMP/fixture.err"
grep -Fq 'G6.91-WIDE-LESS-FIXTURES=18' "$TMP/fixture.out"
test "$(wc -l <"$TMP/physical/cases.tsv")" -eq 18
REPORT="${SENS_LESS_CONTEXT_REPORT:-$TMP/less-results.json}"
timeout 1500s python3 scripts/test-less-context-compiler.py \
  "$TMP/bin/senswidelesskontekst" "$TMP/physical" "$REPORT"
test -s "$REPORT"
python3 - "$REPORT" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
assert data["byte_identical_elf"] == data["executed_elf"] == 18
assert data["samples_per_mode"] == 108
assert len(data["raw"]["old"]) == len(data["raw"]["new"]) == 108
assert data["negative_fixtures"] == 18
assert data["no_cross_program_cache"] is True
assert data["energy"] == "NOT_MEASURED"
assert data["oracle"].startswith("NOT_VERIFIED")
print("МЕНШЕ-КОНТЕКСТ-ДОКАЗ-ГОТОВО profiles=2 signedD12=18 native=18 negatives=18")
PY
