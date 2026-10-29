#!/usr/bin/env bash
# Справжній Lazarus Core4 виклик, без текстового семантичного dispatch.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v lazbuild >/dev/null || { echo 'LCL-CORE4-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-CORE4-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
bash ./scripts/test-core4runtime.sh
mkdir -p build/lcl-core4/bin build/lcl-core4/units
lazbuild --ws=gtk2 --build-all gui/core4-vykonannia.lpi
BIN="$ROOT/build/lcl-core4/bin/core4-vykonannia"
test -x "$BIN" || { echo 'LCL-CORE4-БЛОКЕР: немає виконуваного файлу' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Існуюче ім'я symlink не означає FileExists=true, але його не можна замінювати.
ln -s "$TMP/неіснуюча-ціль.sens" "$TMP/висяче-посилання.sens"
set +e
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$ROOT" "$TMP" >"$TMP/звіт" 2>"$TMP/помилки"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || [ -s "$TMP/помилки" ]; then
  echo "LCL-CORE4-ПОМИЛКА-ПЕРЕВІРКИ код=$STATUS" >&2
  cat "$TMP/помилки" >&2
  cat "$TMP/звіт" >&2
  exit 1
fi
test -L "$TMP/висяче-посилання.sens"
test ! -e "$TMP/неіснуюча-ціль.sens"
grep -F 'LCL-CORE4-ГАРАЗД' "$TMP/звіт"
grep -F 'LCL-CORE4-D7-ГАРАЗД визначень=3 повні-біти=так спільний-префікс=не-колізія усічене=відхилено повторне-завантаження=атомарно' "$TMP/звіт"
grep -F 'LCL-CORE4-ПАКЕТ-ГАРАЗД форм=3 атомарно=так межа=64' "$TMP/звіт"
grep -F 'LCL-CORE4-D2-АДРЕСА-ГАРАЗД close=31 eof=33 трити=точні атомарно=так' "$TMP/звіт"
grep -F 'LCL-CORE4-ЕКСПОРТ-ГАРАЗД слів=3 побайтово=точно перезапис=ні знімок=лише-після-виконання' "$TMP/звіт"
grep -F 'LCL-CORE4-АРХІВ-ГАРАЗД слів=3 W1-W24-W1 координати=точні відмова=атомарно runtime=не-потрібен' "$TMP/звіт"
grep -F 'LCL-CORE4-ГРУПА-ГАРАЗД файлів=3 W24=не-домен пізня-відмова=атомарно повторне-виконання=так межа=8' "$TMP/звіт"
grep -F 'D24=точні-біти Wn=не-домен історія=32 REPL=ні' "$TMP/звіт"
echo 'LCL-CORE4-ЗБІРКА-ГАРАЗД Lazarus=GTK2-Xvfb binary-Core4=виконано'
