#!/usr/bin/env bash
# G6.59 — реальний FPC і виміри без зміни жодного SENS закону.
# Існуючі регресії спершу виконуються без полегшення негативів.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'НАТИВНІ-ЧАСОВІ-ВИМІРИ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
FPC_BIN=${FPC:-fpc}
for program in "$FPC_BIN" python3 git timeout readelf objdump cmp; do
  command -v "$program" >/dev/null || {
    echo "НАТИВНІ-ЧАСОВІ-ВИМІРИ-БЛОК: немає $program" >&2
    exit 127
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test -x "$ROOT/sens-oracle/target/release/sens"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(eq-operands . admitted-atoms-only)' external/sens/contracts/language-contract-12.lisp
grep -Fq '0010110 — SYN' external/sens/lib/domains/d7.lisp

# Збережено всі попередні машинні позитиви, негативи, ELF geometry.
timeout 240s bash ./scripts/test-sensmashyna.sh

OUT="$ROOT/build/m0.2/benchmark-native-d3"
mkdir -p "$OUT/bin" "$OUT/units"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Окремі OPTIMIZED збірки для замірів — не вимірюємо -gl/-gh debug.
# Ліміти -Cr/-Co/-Ci лишаються ввімкненими, жодного unsafe fast-path.
for pair in \
  "src/sensmashyna.lpr sensmashyna" \
  "src/sensvykon.lpr sensvykon" \
  "src/senst5m.lpr senst5m" \
  "scripts/test-sensmashyna.pas test-sensmashyna"; do
  read -r source target <<< "$pair"
  timeout 120s "$FPC_BIN" -B -O2 -Mobjfpc -Cr -Co -Ci \
    -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
    "-o$target" "$ROOT/$source"
done
mkdir -p "$TMP/свідки"
timeout 30s "$OUT/bin/test-sensmashyna" "$ROOT/external/sens" "$TMP/свідки"
# Ті ж самі повністю допущені фізичні свідки незалежного Rust/Zig REPL.
python3 scripts/benchmark-native-d3.py \
  --корінь "$ROOT" --свідки "$TMP/свідки" \
  --машина "$OUT/bin/sensmashyna" --виконавець "$OUT/bin/sensvykon" \
  --читач "$OUT/bin/senst5m" \
  --оракул "$ROOT/sens-oracle/target/release/sens" \
  --вихід "$OUT" --повтори "${SENS_BENCH_REPEATS:-7}"
test -s "$OUT/виміри.json"
test -s "$OUT/звіт.md"
python3 - "$OUT/виміри.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    report = json.load(handle)
assert len(report["форми"]) == 4
assert report["незалежний_SENS_SHA"] == "1f1bf676eeac605e065035d9dd2adaae807f1788"
assert report["негативів_компаратора"] == 7
for entry in report["форми"]:
    assert len(entry["часи"]) == 4
    for cell in entry["часи"].values():
        assert cell["повторів"] >= 3
        assert 0 <= cell["мін_мс"] <= cell["медіана_мс"] <= cell["р95_мс"] <= cell["макс_мс"]
PY
echo 'НАТИВНІ-ЧАСОВІ-ВИМІРИ-ПОВНІ-ГАРАЗД FPC=оптимізований профілів=4 форми=4 SENS-оракул=незалежний JSON=готовий'
