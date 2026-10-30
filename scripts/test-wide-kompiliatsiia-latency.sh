#!/usr/bin/env bash
# G6.173 — однакова фізична програма → три перевірені compiler host API.
# Міряємо wall-clock до готового ELF, а не енергію CPU або runtime мови.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in timeout fpc python3 git readelf mktemp; do
  command -v "$tool" >/dev/null || {
    echo "КОМПІЛЯТОР-ЧАС-БЛОК: відсутній $tool" >&2
    exit 127
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'КОМПІЛЯТОР-ЧАС-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
timeout 20s python3 scripts/test-wide-kompiliatsiia-latency.py --самоперевірка
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ -s "$f" ]] && { echo "--- $f" >&2; tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidekadrovyelf.lpr senswidekadrovyelf' \
  'src/senswidesesiiaelf.lpr senswidesesiiaelf'; do
  read -r path name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$path" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2
      exit 1
    }
  [[ -x "$TMP/bin/$name" ]]
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
RESULT="$TMP/result.json"
if [[ -n "${SENS_LATENCY_JSON:-}" ]]; then RESULT="$SENS_LATENCY_JSON"; fi
timeout 900s python3 "$ROOT/scripts/test-wide-kompiliatsiia-latency.py" \
  "$TMP/bin/senswidefrontelf" "$TMP/bin/senswidekadrovyelf" \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  "$(command -v readelf)" "$RESULT" \
  >"$TMP/bench.out" 2>"$TMP/bench.err" || {
    cat "$TMP/bench.err" >&2
    exit 1
  }
grep -Fxq 'G6.173-КОМПІЛЯТОР-ЧАС-ПЕРЕВІРЕНО cases=16 methods=3 rounds=6 machine=16 selftest=10 negatives=3 energy=NOT_MEASURED' "$TMP/bench.out"
timeout 20s python3 - "$RESULT" <<'PY'
import json, pathlib, sys
d = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert d["схема"] == "sens-native-compiler-latency/1"
assert d["енергія"] == d["апаратний_RAPL"] == "NOT_MEASURED"
assert d["фізичні_програми"] == 16 and len(d["sha256_машин"]) == 16
assert d["раундів_на_метод"] == 6 and len(d["компілятори"]) == 3
assert sorted(len(v["раунди_нс"]) for v in d["компілятори"].values()) == [6, 6, 6]
print("G6.173-JSON-ФІЗИЧНИЙ-ДОКАЗ-OK")
PY
echo 'G6.173-FPC-ELF-МАШИННО-ПЕРЕВІРЕНО'
