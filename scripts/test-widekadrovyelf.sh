#!/usr/bin/env bash
# G6.160 — 16 незалежних фізичних T5M → один FPC процес → 16 ELF.
# Перевіряє машинне виконання, побайтовий результат і відмови цілих пакетів.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in timeout fpc python3 git readelf mktemp; do
  command -v "$tool" >/dev/null || { echo "ШИРОКІ-КАДРИ-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "ШИРОКІ-КАДРИ-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP=$(mktemp -d)
trap 'rc=$?; if (( rc )); then for f in "$TMP"/*.build "$TMP"/*.err; do [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidekadrovyelf.lpr senswidekadrovyelf'; do
  read -r source name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2
      exit 1
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
timeout 180s python3 "$ROOT/scripts/test-widekadrovyelf.py" \
  "$TMP/bin/senswidekadrovyelf" "$TMP/bin/senswidefrontelf" \
  "$TMP/physical" "$(command -v readelf)" \
  >"$TMP/verification.out" 2>"$TMP/verification.err" || {
    cat "$TMP/verification.err" >&2
    exit 1
  }
grep -Fxq 'G6.160-БАГАТОКАДРОВИЙ-ELF-ГОТОВО позитиви=16 негативи=12 відновлення=2' "$TMP/verification.out"
if grep -Fq 'unfreed memory blocks' "$TMP/generator.err"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/generator.err"
fi
echo 'G6.160-МАШИННИЙ-КАДРОВИЙ-ELF-ПРОЙДЕНО'
