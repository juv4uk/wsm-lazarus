#!/usr/bin/env bash
# G6.38 — фізичні D3 виконання реального Linux ELF через спільний probe.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИНА-ПЯТЬ-D3-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
OUT="$ROOT/build/m0.2/elfprobe-all"
mkdir -p "$OUT/bin" "$OUT/units"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-elfprobe-all "$ROOT/scripts/test-elfprobe-all.pas"
timeout 120s "$OUT/bin/test-elfprobe-all" "$ROOT/external/sens"
# Не маскуємо регресійне падіння попереднього single-D3 probe:
# Lazarus/LCL workflow lcl-elf-probe.yml запускається окремо,
# бо змінився саме src/wsm.elfprobe.pas.
# Незалежний ELF64 guard і його 36 негативних геометричних мутацій:
timeout 120s bash "$ROOT/scripts/test-elfgeometry.sh"
echo 'МАШИНА-ПЯТЬ-D3-CI-ГАРАЗД один-probe=5 профілів Linux-ELF=22 негативи=16 geometric=36'
