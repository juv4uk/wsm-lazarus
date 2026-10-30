#!/usr/bin/env bash
# G6.64 — справжнє фізичне порівняння 4 D3 EQ ELF із C/Rust/FPC.
# Окрема від енергетичного RAPL гілка: ENERGY_NOT_MEASURED у CI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-КОНТРОЛЬ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc gcc rustc python3 timeout readelf cmp git; do
  command -v "$tool" >/dev/null || {
    echo "ЕЛФ-КОНТРОЛЬ-БЛОК: немає $tool" >&2; exit 127;
  }
done
test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
test -x sens-oracle/target/release/sens
python3 scripts/benchmark-elf-porivniannia.py \
  --корінь . --свідки . --машина /bin/true \
  --вихід build/не-створювати --самотест

# Незалежний SENS REPL та машинні byte-exact свідки вже перевіряє
# наявний G6.59. Це не наша копія мовного oracle.
timeout 1200s bash scripts/benchmark-native-d3.sh
OUT="$ROOT/build/m0.2/benchmark-elf-porivniannia"
mkdir -p "$OUT/units" "$OUT/bin" "$OUT/svidky"
timeout 120s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-sensmashyna "$ROOT/scripts/test-sensmashyna.pas"
timeout 60s "$OUT/bin/test-sensmashyna" "$ROOT/external/sens" "$OUT/svidky"
python3 scripts/benchmark-elf-porivniannia.py \
  --корінь "$ROOT" --свідки "$OUT/svidky" \
  --машина "$ROOT/build/m0.2/benchmark-native-d3/bin/sensmashyna" \
  --вихід "$OUT/zvit" --повтори "${SENS_ELF_COMPARE_REPEATS:-30}" --зерно 6464
python3 - "$OUT/zvit/виміри.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)
assert result["енергія"] == "ENERGY_NOT_MEASURED"
assert result["негативів_компаратора"] == 9
assert result["pinned_SENS_SHA"] == "2c498b35af53c085450eac6f51b87facf7f9aa47"
assert len(result["виконувані"]) == 16
assert len(result["сирі_виміри"]) == 16 * result["метод"]["повторів"]
assert len(result["підсумки"]) == 16
assert all(v["повторів"] >= 30 and v["медіана_мс"] >= 0
           for v in result["підсумки"].values())
assert set(row["виконавець"] for row in result["сирі_виміри"]) == {
    "sens-elf", "c-gcc", "rust", "free-pascal"
}
PY
echo 'ЕЛФ-КОНТРОЛЬ-ГАРАЗД 4 canonical SENS проти C/Rust/FPC; виміри=480+ oracle=pinned енергія=ENERGY_NOT_MEASURED'
