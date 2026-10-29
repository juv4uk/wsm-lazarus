#!/usr/bin/env bash
# G6.71: справжній FPC backend, Lazarus/LCL GTK2 + JSON host dashboard.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
for cmd in lazbuild xvfb-run fpc python3 timeout readelf objdump cmp; do
  command -v "$cmd" >/dev/null || { echo "ЛКЛ-ЧАС-БЛОК: немає $cmd" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
mkdir -p build/lcl-elf-chas/bin build/lcl-elf-chas/units
timeout 300s lazbuild --widgetset=gtk2 --build-all gui/sens-elf-chas-ogliad.lpi
BIN="$ROOT/build/lcl-elf-chas/bin/sens-elf-chas-ogliad"
test -x "$BIN"
# Виконуваний backend перевіряється ОКРЕМО: 8 ELF, 11 негативів.
timeout 600s bash scripts/test-sensmashyna.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP" <<'PY'
import copy
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
forms = ("тотожні-00", "тотожні-01", "тотожні-10", "тотожні-11")
engines = ("sens-elf", "c-gcc", "rust", "free-pascal")
stats = {}
files = {}
samples = []
for form in forms:
    for engine in engines:
        key = form + "/" + engine
        stats[key] = {"повторів": 30, "медіана_мс": 0.5, "р95_мс": 0.5,
                      "мін_мс": 0.5, "макс_мс": 0.5}
        files[key] = {"sha256": "a" * 64, "ELF_байтів": 240}
for block in range(1, 31):
    for form in forms:
        for engine in engines:
            samples.append({"блок": block, "випадок": form,
                            "виконавець": engine, "наносекунд": 500000})
good = {"схема": "sens-elf-c-rust-fpc-coldstart/1",
        "pinned_SENS_SHA": "1f1bf676eeac605e065035d9dd2adaae807f1788",
        "енергія": "ENERGY_NOT_MEASURED",
        "метод": {"повторів": 30}, "підсумки": stats,
        "виконувані": files, "сирі_виміри": samples}
def write(name, doc):
    (root / name).write_text(json.dumps(doc, ensure_ascii=False),
                             encoding="utf-8")
write("добрий.json", good)
bad = copy.deepcopy(good)
bad["енергія"] = "1.23 Дж"
write("хибна-енергія.json", bad)
bad = copy.deepcopy(good)
bad["схема"] = "unverified/1"
write("хибна-схема.json", bad)
bad = copy.deepcopy(good)
bad["сирі_виміри"][1] = bad["сирі_виміри"][0].copy()
write("хибна-матриця.json", bad)
PY
timeout 60s xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/добрий.json" "$TMP/хибна-енергія.json" \
  "$TMP/хибна-схема.json" "$TMP/хибна-матриця.json" \
  >"$TMP/stdout" 2>"$TMP/stderr"
test ! -s "$TMP/stderr"
grep -F 'ЛКЛ-ELF-ЧАС-ГАРАЗД Lazarus=GTK2 рядків=16' "$TMP/stdout"
echo 'ЛКЛ-ELF-ЧАС-ЗБІРКА-ГАРАЗД FPC=реальний ELF=8 LCL=GTK2/Xvfb JSON=захищений ENERGY_NOT_MEASURED'
