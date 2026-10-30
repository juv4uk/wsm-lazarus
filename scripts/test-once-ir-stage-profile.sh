#!/usr/bin/env bash
# G6 / #848 — FPC-only профіль етапів, не компіляторний semantic patch.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout python3 mktemp grep; do
  command -v "$tool" >/dev/null || { echo "ПРОФІЛЬ-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ПРОФІЛЬ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git rev-parse HEAD)" = "${EXPECTED_HEAD_SHA:-$(git rev-parse HEAD)}" || {
  echo 'ПРОФІЛЬ-БЛОК: не точний PR HEAD' >&2; exit 1;
}
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if ((rc)); then
    for file in "$TMP"/*.log; do
      [[ -f "$file" ]] && { echo "--- $file" >&2; tail -n 35 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for entry in 'scripts/test-irwidefront.pas:test-irwidefront' \
             'scripts/test-once-ir-stage-profile.pas:test-once-ir-stage-profile'; do
  source="${entry%%:*}"
  name="${entry##*:}"
  timeout 150s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.log" 2>&1 || {
      cat "$TMP/$name.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>&1 || { cat "$TMP/fixtures.log" >&2; exit 1; }
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.log"
timeout 220s python3 scripts/test-once-ir-stage-profile.py \
  "$TMP/bin/test-once-ir-stage-profile" "$TMP/physical" "$TMP/report.json" \
  | tee "$TMP/profile.log"
test -s "$TMP/report.json"
if [[ -n "${SENS_STAGE_PROFILE_DEST:-}" ]]; then
  cp "$TMP/report.json" "$SENS_STAGE_PROFILE_DEST"
fi
echo 'ПРОФІЛЬ-ЕТАПІВ-ФІЗИЧНИЙ-ДОКАЗ-ГОТОВО'
