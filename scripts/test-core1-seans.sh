#!/usr/bin/env bash
# G5.67 — справжній FPC + повторне використання існуючих Core1 свідків.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
for cmd in fpc timeout python3 mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "CORE1-СЕАНС-БЛОК: відсутній $cmd" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for log in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 30 "$log" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"
for entry in 'src/senscore1seans.lpr:senscore1seans' 'scripts/test-core1-paket.pas:test-core1-paket'; do
  IFS=: read -r source name <<< "$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" -o"$name" "$ROOT/$source" \
    >"$TMP/build-$name.log" 2>&1 || { cat "$TMP/build-$name.log" >&2; exit 1; }
done
timeout 60s "$TMP/bin/test-core1-paket" "$ROOT/external/sens" "$ROOT" "$TMP" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'CORE1-PAKET-FIXTURES-OK' "$TMP/fixtures.out"
timeout 120s python3 scripts/test-core1-seans.py "$TMP/bin/senscore1seans" "$ROOT" "$TMP"
