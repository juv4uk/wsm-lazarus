#!/usr/bin/env bash
# G2.55 — вичерпне FPC свідчення exact binder над pinned D1–D10.
# Інтегрується чинним test-verified-all.sh; без нового workflow та apt.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
test -f "$ROOT/external/sens/lib/domains/d10.lisp" || {
  echo 'ПРОЄКЦІЇ-ВСІ-ПОМИЛКА: немає pinned SENS' >&2
  exit 2
}
mkdir -p "$ROOT/build"
TMP=$(mktemp -d "$ROOT/build/g2-55-pinned-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-verified-bind-vsi-proektsii \
  "$ROOT/scripts/test-verified-bind-vsi-proektsii.pas" \
  >"$TMP/build.log" 2>&1; then
  tail -40 "$TMP/build.log" >&2
  exit 1
fi
if ! timeout 120s "$TMP/bin/test-verified-bind-vsi-proektsii" \
  "$ROOT/external/sens" >"$TMP/run.log" 2>&1; then
  sed -n '1,40p' "$TMP/run.log" >&2
  exit 1
fi
grep -Eq '^ПРОЄКЦІЇ-ВСІ-ГАРАЗД рядків=2046 колонок=6 непорожніх=[0-9]+ унікальних=[0-9]+ неоднозначних=[0-9]+ порожніх=[0-9]+ відмов-порожніх=60$' "$TMP/run.log" || {
  cat "$TMP/run.log" >&2
  echo 'ПРОЄКЦІЇ-ВСІ-ПОМИЛКА: немає доказового підсумку' >&2
  exit 1
}
grep -F 'ПРОЄКЦІЇ-ВСІ-ГАРАЗД' "$TMP/run.log"
echo 'VERIFIED-BIND-PASS exact=D1-D10 проєкцій=6 рядків=2046 семантика=не-створюється'
