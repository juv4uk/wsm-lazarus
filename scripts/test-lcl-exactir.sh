#!/usr/bin/env bash
# Справжня Lazarus/LCL перевірка приватного ExactIR, не виконання SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ТОЧНЕ-IR-БЛОК: відсутній lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ТОЧНЕ-IR-БЛОК: відсутній xvfb-run' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
bash ./scripts/test-exactir.sh
bash ./scripts/test-exactirguard.sh
mkdir -p build/lcl-exactir/bin build/lcl-exactir/units build/m0.2/bin build/m0.2/test-units
lazbuild --ws=gtk2 gui/exactir-inspector.lpi
test -x build/lcl-exactir/bin/exactir-inspector
FPC_BIN=${FPC:-fpc}
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/test-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '10 111 00 0 000 01\n' > "$TMP/список.words"
printf '10 1 0 11 000 01\n' > "$TMP/пара.words"
# Два D2 корені: у першому один точний D1 листок, другий — D1:0.
# CLI створює канонічні T5M байти; не виводимо фізичний код із .lisp.
printf '10 1 01 0\n' > "$TMP/два-корені.words"
"$ROOT/build/m0.2/bin/senst5m" --пакувати-слова "$TMP/список.words" > "$TMP/список.sens"
"$ROOT/build/m0.2/bin/senst5m" --пакувати-слова "$TMP/пара.words" > "$TMP/пара.sens"
"$ROOT/build/m0.2/bin/senst5m" --пакувати-слова "$TMP/два-корені.words" > "$TMP/два-корені.sens"
printf '\363' > "$TMP/зіпсовано.sens"
LC_ALL=C.UTF-8 xvfb-run -a "$ROOT/build/lcl-exactir/bin/exactir-inspector" \
  --самоперевірка "$TMP/список.sens" "$TMP/пара.sens" "$TMP/зіпсовано.sens" "$TMP/два-корені.sens" \
  | tee "$TMP/свідчення.txt"
grep -Fq 'LCL-ТОЧНЕ-IR-ГАРАЗД' "$TMP/свідчення.txt"
grep -Fq 'LCL-ПІДДЕРЕВА-ГАРАЗД' "$TMP/свідчення.txt"
echo 'LCL-ПРОЄКЦІЯ-IR-ГАРАЗД Lazarus=справжній GTK2=Xvfb приватне-IR=так семантика=НЕ-ДОВЕДЕНА'
