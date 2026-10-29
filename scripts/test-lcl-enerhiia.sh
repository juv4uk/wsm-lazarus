#!/usr/bin/env bash
# Реальна FPC та Lazarus/GTK2 перевірка фізичних host-знімків RAPL.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo "ЛКЛ-ЕНЕРГІЯ-БЛОК: потрібен FPC" >&2; exit 127; }
command -v lazbuild >/dev/null || { echo "ЛКЛ-ЕНЕРГІЯ-БЛОК: потрібен Lazarus" >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo "ЛКЛ-ЕНЕРГІЯ-БЛОК: потрібен Xvfb" >&2; exit 127; }
command -v timeout >/dev/null || { echo "ЛКЛ-ЕНЕРГІЯ-БЛОК: потрібен timeout" >&2; exit 127; }
# Чинний нативний знімач єдиний рахує фізичні modulo/range; його тести
# включають реальний FPC build, 20 механічних перевірок і негативи.
bash scripts/energy/test-sensrapl.sh
mkdir -p build/lcl-enerhiia/bin build/lcl-enerhiia/units
lazbuild --widgetset=gtk2 --build-all gui/sens-enerhiia.lpi
BIN="$ROOT/build/lcl-enerhiia/bin/sens-enerhiia"
SENSOR="$ROOT/build/m0.2/bin/sensrapl"
test -x "$BIN" && test -x "$SENSOR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/powercap/intel-rapl:0/intel-rapl:0:0"
printf 'package-0\n' > "$TMP/powercap/intel-rapl:0/name"
printf '99999990\n' > "$TMP/powercap/intel-rapl:0/energy_uj"
printf '100000000\n' > "$TMP/powercap/intel-rapl:0/max_energy_range_uj"
printf 'core\n' > "$TMP/powercap/intel-rapl:0/intel-rapl:0:0/name"
printf '4\n' > "$TMP/powercap/intel-rapl:0/intel-rapl:0:0/energy_uj"
printf '500000000\n' > "$TMP/powercap/intel-rapl:0/intel-rapl:0:0/max_energy_range_uj"
"$SENSOR" --знімок "$TMP/powercap" > "$TMP/до.tsv"
printf '20\n' > "$TMP/powercap/intel-rapl:0/energy_uj"
printf '25\n' > "$TMP/powercap/intel-rapl:0/intel-rapl:0:0/energy_uj"
"$SENSOR" --знімок "$TMP/powercap" > "$TMP/після.tsv"
"$SENSOR" --різниця "$TMP/до.tsv" "$TMP/після.tsv" 50000 1000 > "$TMP/підтверджено.tsv"
grep -Fqx $'intel-rapl:0\tpackage-0\t99999990\t20\t100000000\t30' "$TMP/підтверджено.tsv"
grep -Fqx $'intel-rapl:0/intel-rapl:0:0\tcore\t4\t25\t500000000\t21' "$TMP/підтверджено.tsv"
# Негативний RAPL1 на останньому слові: FPC повертає nonzero і не
# публікує часткову різницю навіть якщо першу зону вже перевірено.
cp "$TMP/після.tsv" "$TMP/зіпсовано.tsv"
sed -i 's/500000000/500000001/' "$TMP/зіпсовано.tsv"
if "$SENSOR" --різниця "$TMP/до.tsv" "$TMP/зіпсовано.tsv" 50000 1000 \
    > "$TMP/хибний-вивід" 2> "$TMP/хибна-діагностика"; then
  echo 'ЛКЛ-ЕНЕРГІЯ-ПОМИЛКА: прийнято підміну діапазону' >&2; exit 1
fi
test ! -s "$TMP/хибний-вивід"
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=10s 180s \
  xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$SENSOR" "$TMP/до.tsv" "$TMP/після.tsv" \
  "$TMP/зіпсовано.tsv" > "$TMP/лкл-лог" 2> "$TMP/лкл-помилки"
test ! -s "$TMP/лкл-помилки"
grep -F 'ЛКЛ-ЕНЕРГІЯ-ГАРАЗД Lazarus=GTK2' "$TMP/лкл-лог"
echo 'ЛКЛ-ЕНЕРГІЯ-ЗБІРКА-ГАРАЗД FPC=3.2 Lazarus=GTK2 Xvfb=так позитивні=так негативні=так energy=ENERGY_NOT_MEASURED'
