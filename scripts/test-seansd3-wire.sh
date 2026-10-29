#!/usr/bin/env bash
# G5.55 — реальний довгоживучий D3/ук host-канал, не .sens і не REPL.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
bash ./scripts/check-pin.sh
bash ./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'СЕАНС-Д3-БЛОК: потрібен справжній FPC' >&2; exit 127;
}
command -v python3 >/dev/null || {
  echo 'СЕАНС-Д3-БЛОК: потрібен Python3 subprocess' >&2; exit 127;
}
# Існуючі синтетичні host-негативи І чинний РЕАЛЬНИЙ D3 evaluator
# мають проходити без послаблення перед перевіркою нового CLI.
bash ./scripts/test-sessionwire.sh
mkdir -p "$ROOT/build/seansd3-wire/units" "$ROOT/build/seansd3-wire/bin"
# -gh заборонено на stdout справжнього двійкового host-протоколу:
# heaptrc додає текст до фізичних байтів; старі FPC тести лишаються.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/seansd3-wire/units" \
  -FE"$ROOT/build/seansd3-wire/bin" \
  -osensseansd3 "$ROOT/src/sensseansd3.lpr"
timeout 90s python3 "$ROOT/scripts/test-seansd3-wire.py" \
  "$ROOT/build/seansd3-wire/bin/sensseansd3" "$ROOT"
echo 'СЕАНС-Д3-ХОСТ-ПРОТОКОЛ-ГАРАЗД FPC=справжній шість-проєкцій=тільки-pinned host=ук не-.sens persistent-process=так full-REPL=ні'
