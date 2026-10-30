#!/usr/bin/env bash
# G2.58 — перевірка pinned Dn open-fail в наявному verified-all.
# Справжній checked FPC; один build, два відсутні домени, recovery.
# Ніякого Rust/Zig, додаткового apt чи нового workflow.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for tool in fpc git timeout cp rm mktemp mkdir grep tail; do
  command -v "$tool" >/dev/null || {
    echo "G2-58-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  "2c498b35af53c085450eac6f51b87facf7f9aa47"
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if (( rc )); then
    echo "G2-58-ПРОВАЛ code=$rc" >&2
    for f in "$TMP"/*.log; do
      if [[ -s "$f" ]]; then
        echo "--- $f" >&2
        sed -n '1,14p' "$f" >&2
        tail -n 10 "$f" >&2
      fi
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/authority/lib/domains"
cp "$ROOT"/external/sens/lib/domains/d{1..10}.lisp \
  "$TMP/authority/lib/domains/"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-bind-open-fail "$ROOT/scripts/test-bind-open-fail.pas" \
  >"$TMP/build.log" 2>&1 || {
    tail -n 80 "$TMP/build.log" >&2
    exit 1
  }
test -x "$TMP/bin/test-bind-open-fail"
for missing in 7 1; do
  rm "$TMP/authority/lib/domains/d$missing.lisp"
  timeout 120s "$TMP/bin/test-bind-open-fail" \
    "$TMP/authority" "$ROOT/external/sens" "$missing" \
    >"$TMP/negative-$missing.log" 2>&1
  grep -Fxq "G2-58-BIND-MISSING-PASS domain=$missing partial=none recovery=all-10" \
    "$TMP/negative-$missing.log"
  cp "$ROOT/external/sens/lib/domains/d$missing.lisp" \
    "$TMP/authority/lib/domains/d$missing.lisp"
done
echo "VERIFIED-BIND-OPEN-FAIL-PASS fpc=checked missing=D7,D1 partial=none recovery=all-10 oracle=NOT-RUN energy=NOT-MEASURED"
