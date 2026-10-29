#!/usr/bin/env bash
# G5.33 — справжній Lazarus GTK2, FPC, дочірній pinned Core4 та негативи.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ПАКЕТ-БЛОКЕР: потрібен lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ПАКЕТ-БЛОКЕР: потрібен Xvfb' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'LCL-ПАКЕТ-БЛОКЕР: потрібен timeout' >&2; exit 127; }
./scripts/check-pin.sh
# Збережені всі попередні FPC тести каналу й їхні негативні сценарії.
timeout 180 bash ./scripts/test-core4wireclient.sh
mkdir -p build/lcl-core4-paket/units
timeout 120 lazbuild --ws=gtk2 --build-all gui/core4-paket-okno.lpi
GUI="$ROOT/build/lcl-core4-paket/core4-paket-okno"
CHILD="$ROOT/build/m0.2/bin/senscore4kanal"
test -x "$GUI" && test -x "$CHILD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! LC_ALL=C.UTF-8 timeout 60 xvfb-run -a -s '-screen 0 1440x900x24' \
  "$GUI" --самоперевірка "$ROOT" "$CHILD" >"$TMP/out" 2>"$TMP/err"; then
  cat "$TMP/out" >&2
  cat "$TMP/err" >&2
  exit 1
fi
cat "$TMP/out"
cat "$TMP/err" >&2
grep -Fq 'LCL-CORE4-ПАКЕТ-ГАРАЗД' "$TMP/out"
grep -Fq 'W1-W24=побайтово пізня-помилка=атомарна' "$TMP/out"
grep -Fq 'T5M=відхилено lisp=відхилено відновлення=так' "$TMP/out"
grep -Fq 'LCL-CORE4-УКР-ГАРАЗД' "$TMP/out"
grep -Fq 'укр=лише-явно D7=pinned T5M=byte-exact' "$TMP/out"
grep -Fq 'UTF8=відхилено unknown=відхилено PID=один' "$TMP/out"
echo 'LCL-CORE4-ПАКЕТ-CI-ГАРАЗД Lazarus=справжній FPC=справжній канал=окремий укр=точне-перетворення'
