#!/usr/bin/env bash
# G6.228 — без нового workflow: фізичний D3:101 та Linux host I/O.
# Перевірити ET_EXEC і ET_DYN, 4 пари фізичних D1, 15 admission-негативів,
# 16 реальних EBADF/ENOSPC, 8 відновлень і незмінний T5M backend.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
timeout 240s bash scripts/test-elfeq.sh
timeout 240s bash scripts/test-elfeqt5m.sh
echo 'VEQ-WRITE-PASS fpc=checked ET_EXEC=так ET_DYN=так machine=CMP/JNE oracle=NOT_RUN energy=NOT_MEASURED'
