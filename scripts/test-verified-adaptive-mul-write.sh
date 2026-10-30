#!/usr/bin/env bash
# G6.235 — один FPC checked proof усіх D12/D24 IMUL machine + write negatives.
# Підхоплює існуючий scripts/test-verified-all.sh, workflow не додає.
# Тут лише host Linux fd1 і фізичні T5M, НЕ новий SENS закон чи RAPL.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
timeout 700s bash scripts/test-elfd12mulpotikadaptive.sh >"$LOG" 2>&1 || {
  tail -n 85 "$LOG" >&2
  exit 1
}
grep -Fxq 'АДАПТИВНЕ-IMUL-WRITE-PASS small=1 wide=1 closed=2 full=2 recovery=4 oracle=NOT-RUN energy=NOT-MEASURED' "$LOG"
grep -Fq 'АДАПТИВНЕ-IMUL-ГОТОВО small=26 wide=8 real-elf=68' "$LOG"
echo 'VERIFIED-ADAPTIVE-IMUL-WRITE-PASS fpc=checked small=26 wide=8 closed=2 full=2 recovery=4 oracle=NOT-RUN energy=NOT-MEASURED'
