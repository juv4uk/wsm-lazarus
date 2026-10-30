#!/usr/bin/env bash
# G6.67 — окремий чесний вимір компіляції фізичних ELF, НЕ RAPL.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'АВТ-КОМПІЛЯЦІЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc gcc rustc python3 timeout git cmp; do
  command -v "$tool" >/dev/null || {
    echo "АВТ-КОМПІЛЯЦІЯ-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
test -x sens-oracle/target/release/sens
test -s external/sens/lib/domains/d7.lisp
test -s external/sens/contracts/language-contract-12.lisp
# Негативи перед розгортанням стенду: немає дозволу на умовний green.
python3 scripts/benchmark-kompiliatsiia-aot.py --самотест
# Чинний незалежний pinned SENS Rust/Zig REPL підтверджує кожний
# канонічний .sens випадок до жодного вимірюваного AOT запуску.
timeout 1500s bash scripts/benchmark-native-d3.sh
OUT="$ROOT/build/m0.2/benchmark-kompiliatsiia-aot"
mkdir -p "$OUT/units" "$OUT/bin" "$OUT/svidky"
timeout 150s fpc -B -O2 -Mobjfpc -Cr -Co -Ci \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-sensmashyna "$ROOT/scripts/test-sensmashyna.pas"
timeout 90s "$OUT/bin/test-sensmashyna" "$ROOT/external/sens" "$OUT/svidky"
test ! -e "$OUT/виміри.json"
timeout 2400s python3 scripts/benchmark-kompiliatsiia-aot.py \
  --корінь "$ROOT" --свідки "$OUT/svidky" \
  --машина "$ROOT/build/m0.2/benchmark-native-d3/bin/sensmashyna" \
  --вихід "$OUT/виміри.json" --повтори "${SENS_AOT_COMPILE_REPEATS:-30}" --зерно 6767
python3 - "$OUT/виміри.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    result = json.load(stream)
assert result["схема"] == "sens-aot-compile-walltime/1"
assert result["енергія"] == "ENERGY_NOT_MEASURED"
assert result["pinned_SENS_SHA"] == "2c498b35af53c085450eac6f51b87facf7f9aa47"
assert result["негативів"] == 25
assert len(result["зразки"]) == 4 and len(result["статистика"]) == 16
assert len(result["сирі_виміри"]) == 16 * result["профіль"]["повторів_кожного"]
assert all(value["кількість"] >= 30 and value["медіана_мс"] > 0
           for value in result["статистика"].values())
assert all(row["компіляція_нс"] > 0 and len(row["elf_sha256"]) == 64
           for row in result["сирі_виміри"])
assert {row["компілятор"] for row in result["сирі_виміри"]} == {
    "sens-elf", "c-gcc", "rust", "free-pascal"
}
print("АВТ-КОМПІЛЯЦІЯ-МАТРИЦЯ-ГАРАЗД raw="
      + str(len(result["сирі_виміри"])) + " oracle=pinned без-RAPL=так")
PY
