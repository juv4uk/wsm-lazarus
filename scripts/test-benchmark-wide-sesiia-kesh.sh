#!/usr/bin/env bash
# G6.175 — тільки FPC + Python stdlib, без Rust/Zig або важких push.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git timeout fpc python3 mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "КЕШ-ПРОФІЛЬ-БЛОК: не встановлено $tool" >&2
    exit 127
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "КЕШ-ПРОФІЛЬ-БЛОК: потрібен Linux x86-64" >&2
  exit 127
}
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidesesiiaelf.lpr senswidesesiiaelf'; do
  read -r src name <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
      cat "$TMP/$name.build" "$TMP/$name.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
timeout 600s python3 scripts/benchmark-wide-sesiia-kesh.py \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" "$TMP/profil.json" \
  >"$TMP/profil.out" 2>"$TMP/profil.err" || {
    cat "$TMP/profil.err" >&2; exit 1;
  }
RAPL_STATUS=NOT-MEASURED
if [[ -n "${SENS_RAPL_ENERGY_PATH:-}" ]]; then RAPL_STATUS=PACKAGE; fi
grep -Fxq "G6.175-КЕШ-ПРОФІЛЬ-ПРОЙДЕНО frames=64 good=62 negative=2 hits=60 misses=2 rounds=6 machine=2 oracle=NOT-CHECKED rapl=$RAPL_STATUS" "$TMP/profil.out"
grep -F 'ЧАС-МЕДІАНА ' "$TMP/profil.out"
test -s "$TMP/profil.json"
python3 - "$TMP/profil.json" <<'PY'
import json
import os
import sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
assert obj["pin_SENS"] == "1f1bf676eeac605e065035d9dd2adaae807f1788"
assert [obj["host_кадрів"], obj["позитивних"], obj["негативних"]] == [64, 62, 2]
assert [obj["кеш_hits"], obj["кеш_misses"], obj["раундів_на_режим"]] == [60, 2, 6]
assert len(obj["без_кешу_час_мс"]) == len(obj["з_кешем_час_мс"]) == 6
assert obj["медіана_без_кешу_мс"] > 0
assert obj["медіана_з_кешем_мс"] > 0
assert obj["енергія"]["стан"] == ("ПАКЕТ-ОС-ВИМІРЯНО" if os.environ.get("SENS_RAPL_ENERGY_PATH") else "НЕ-ВИМІРЯНО")
PY
if [[ -n "${SENS_BENCHMARK_REPORT:-}" ]]; then
  cp "$TMP/profil.json" "$SENS_BENCHMARK_REPORT"
fi
echo 'G6.175-КЕШ-ПРОФІЛЬ-МАШИННИЙ-ГОТОВО'
