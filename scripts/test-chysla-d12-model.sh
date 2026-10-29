#!/usr/bin/env bash
# #522: Python big-int / T5M фізична модель проти двох чинних FPC CLI.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for cmd in fpc python3 timeout mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "D12-МОДЕЛЬ-БЛОК: немає $cmd" >&2; exit 127;
  }
done
./scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
python3 -B scripts/test-chysla-d12-model.py --самоперевірка

# Реальні checked Free Pascal 3.2.x програми, а не Python підміна.
for entry in 'src/senschyslododaty.lpr:senschyslododaty' \
             'src/senschyslopomnozhyty.lpr:senschyslopomnozhyty'; do
  IFS=: read -r src target <<< "$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
    -o"$target" "$ROOT/$src" >"$TMP/$target.log" 2>&1 || {
      cat "$TMP/$target.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$target"
done

timeout 240s python3 -B scripts/test-chysla-d12-model.py \
  "$TMP/bin/senschyslododaty" "$TMP/bin/senschyslopomnozhyty"
