#!/usr/bin/env bash
# G3.32 / #149 — механічна перевірка явної числової проєкції.
# Домен обирає людина; UI/CLI ніколи не виводять його зі значення.
# GUI-частину перевіряє окремий LCL-прогін (тут lazbuild відсутній).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CHYSLOVIY-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/chyslovyi-units build/chyslovyi-bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci \
  -Fu"$ROOT/src" -FU"$ROOT/build/chyslovyi-units" \
  -FE"$ROOT/build/chyslovyi-bin" -otest-chyslovyi \
  "$ROOT/scripts/test-chyslovyi-proiekt.pas" >/dev/null
"$ROOT/build/chyslovyi-bin/test-chyslovyi"
