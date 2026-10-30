#!/usr/bin/env bash
# G6 — scoped pinned tables усередині ОДНОЇ компіляції, PR/manual.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout python3 mktemp grep cp; do
  command -v "$tool" >/dev/null || {
    echo "ПЕРША-КОМПІЛЯЦІЯ-БЛОК: відсутній $tool" >&2
    exit 127
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ПЕРША-КОМПІЛЯЦІЯ-БЛОК: потрібен Linux x86-64' >&2
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
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/authority/lib/domains"
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'scripts/test-pinned-scope.pas test-pinned-scope' \
  'src/senswidesesiiaelf.lpr senswidesesiiaelf'; do
  read -r source name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
    cat "$TMP/$name.build" "$TMP/$name.err" >&2
    exit 1
  }
  test -x "$TMP/bin/$name"
done
cp external/sens/lib/domains/d{1,2,3,4,5,6,7,8,9,10}.lisp "$TMP/authority/lib/domains/"
timeout 40s "$TMP/bin/test-pinned-scope" "$TMP/authority" \
  >"$TMP/scope.out" 2>"$TMP/scope.err"
grep -Fxq 'ПІН-СКОУП-ПРОЙДЕНО domains=10 isolated=так mutation=так errors=так' "$TMP/scope.out"
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
SENS_FIRST_SCOPE_REPORT="$TMP/profile.json" timeout 580s \
  python3 scripts/test-wide-sesiia-first-snapshot.py \
    "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  >"$TMP/profile.out" 2>"$TMP/profile.err" || {
    cat "$TMP/profile.err" >&2
    exit 1
  }
grep -Fxq 'ПЕРША-КОМПІЛЯЦІЯ-ПРОЙДЕНО fresh=16 negative=2 elf-executed=16 parity=byte-exact cycles=3 oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/profile.out"
grep -Fq 'ПЕРША-КОМПІЛЯЦІЯ-ЧАС-НС звичайний=' "$TMP/profile.out"
test -s "$TMP/profile.json"
if [[ -n "${SENS_FIRST_SCOPE_REPORT_DEST:-}" ]]; then
  cp "$TMP/profile.json" "$SENS_FIRST_SCOPE_REPORT_DEST"
fi
echo 'ПЕРША-КОМПІЛЯЦІЯ-МАШИННИЙ-ДОКАЗ-ГОТОВО'
