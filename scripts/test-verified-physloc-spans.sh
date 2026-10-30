#!/usr/bin/env bash
# G1.55: перевіряємо фізичні T5M byte/trit координати через чинний FPC.
# Ніяких нових SENS законів, окремого workflow чи встановлення compiler.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
timeout 180s bash scripts/test-physloc.sh
printf 'VERIFIED-PHYSLOC-SPANS-PASS checked-FPC=так negative=5 recovery=1\n'
