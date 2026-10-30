#!/usr/bin/env bash
# G6.193 — FPC→ELF64 та перша компіляція 16 різних T5M.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'КОНТЕКСТ-D5-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for tool in git fpc python3 timeout mktemp readelf cmp;do
  command -v "$tool" >/dev/null || {
    echo "КОНТЕКСТ-D5-БЛОК: немає $tool" >&2;exit 127;
  }
done
# Найдешевший host-тест запускається ДО pinned/FPC-збірки.
# Справжній stdout ELF і незалежний оракул залишаються в тестах нижче.
timeout 15s python3 scripts/test-add-context-compiler.py --selftest-write
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc));then
    echo "КОНТЕКСТ-D5-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'scripts/test-add-context-fixtures.pas test-add-context-fixtures' \
  'src/senswideaddkontekst.lpr senswideaddkontekst';do
  read -r source executable <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>&1 || {
      cat "$TMP/$executable.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$executable"
done
timeout 20s "$TMP/bin/test-add-context-fixtures" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
test "$(wc -l <"$TMP/physical/cases.tsv")" -eq 16
# СЕНС — саме перша компіляція 16 різних джерел, не FPC build.
if [[ -n "${SENS_ORACLE_BIN:-}" ]];then
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
REPORT="${SENS_ZERO_CONTEXT_REPORT:-$TMP/results.json}"
timeout 1450s python3 scripts/test-add-context-compiler.py \
  "$TMP/bin/senswideaddkontekst" "$TMP/physical" "$REPORT"
test -s "$REPORT"
python3 - "$REPORT" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x["byte_identical_elf"] == x["executed_elf"] == 16
assert x["samples_per_mode"] == 96
assert len(x["raw"]["old"]) == len(x["raw"]["new"]) == 96
assert x["negative_fixtures"] == 11
assert x["no_cross_program_cache"] is True
assert x["oracle"] in ("NOT_VERIFIED", "VERIFIED")
assert x["energy"] == "NOT_MEASURED"
print("КОНТЕКСТ-D5-ВИМІР-ДОКАЗ-ГОТОВО")
PY
# Питання: чому не можна порівнювати кешовані виклики?
# Чому canonical physical ELF мусить бути byte-identical?
# Хто відповідає за lifetime контексту?
# Чому кожній новій програмі потрібні pinned таблиці?
