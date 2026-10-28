#!/usr/bin/env bash
# G2.21 — реальний FPC, повні pinned D1–D10 та атомарна відмова.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ДОМЕННА-ТАБЛИЦЯ-ПОМИЛКА: Free Pascal відсутній' >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/domain-atomic-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/domain-atomic-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-domain "$ROOT/scripts/test-domain.pas"
"$ROOT/build/m0.2/bin/test-domain"
# Чинний pinned loader D1–D10 та його негативні тести незмінні.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/domain-atomic-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-bind "$ROOT/scripts/test-bind.pas"
"$ROOT/build/m0.2/bin/test-bind"
echo 'ДОМЕННА-ТАБЛИЦЯ-CI-ГАРАЗД FPC=справжній pinned=D1-D10 діагностика=строга'
