#!/usr/bin/env bash
# G0.1 — механіка читання документації не визначає закон SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v python3 >/dev/null || {
  echo 'ДОКАЗИ-БЛОК: немає Python 3' >&2; exit 127;
}
python3 scripts/test-evidence-index.py --самоперевірка
./scripts/check-pin.sh
python3 scripts/test-evidence-index.py
# Реальна FPC-регресія гарантує, що CI не підмінив доказ
# структурної таблиці простим «усі файли існують».
timeout 180s bash scripts/test-binaryexec.sh
echo 'ДОКАЗИ-ЗБІРКА-ГАРАЗД Contract12=pin перевірка-посилань=так FreePascal=checked'
