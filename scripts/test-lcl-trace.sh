#!/usr/bin/env bash
# Фізичний LCL/GTK2 smoke: окремий графічний стек, не evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || {
  echo 'LCL-СТЕК-БЛОКЕР: відсутній lazbuild' >&2
  exit 127
}
command -v xvfb-run >/dev/null || {
  echo 'LCL-СТЕК-БЛОКЕР: відсутній xvfb-run' >&2
  exit 127
}
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
mkdir -p build/lcl-trace/units
lazbuild --widgetset=gtk2 --build-all "$ROOT/gui/trace-inspector.lpi"
# Lazarus може розмістити target в unit output dir згідно з версією .lpi;
# обидва шляхи лишаються локальними для нашого окремого проєкту.
BIN="$ROOT/build/lcl-trace/trace-inspector"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/build/lcl-trace/units/trace-inspector"
fi
[[ -x "$BIN" ]] || {
  echo 'LCL-СТЕК-ПРОВАЛ: компіляція не створила виконуваний GUI' >&2
  exit 1
}
TMP=$(mktemp -d "$ROOT/build/lcl-trace/перевірка.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT
xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" --самоперевірка > "$TMP/вихід"
cat "$TMP/вихід"
grep -q 'LCL-СТЕК-ГАРАЗД' "$TMP/вихід"
grep -q 'виконання=ні' "$TMP/вихід"
echo 'LCL-СТЕК-ЗБІРКА-ГАРАЗД GTK2=так xvfb=так src_LCL=ні'
