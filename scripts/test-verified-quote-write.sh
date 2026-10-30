#!/usr/bin/env bash
# G6.224 — спільний PR-only FPC runner, без додаткового workflow/apt.
# Справжній D3:001 T5M → ELF64 із машинним CMP RAX,RDX / JNE.
# Зберегти 7 фізичних позитивів, 9 відмов admission і 4 Linux I/O негативи.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
timeout 240s bash scripts/test-elfquote-t5m.sh
echo 'VQUOTE-WRITE-PASS fpc=checked machine=CMP/JNE oracle=NOT_RUN energy=NOT_MEASURED'
