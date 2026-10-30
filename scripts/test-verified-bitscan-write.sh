#!/usr/bin/env bash
# G6.232 — один checked-FPC прогін існуючого фізичного D12 BSF/BSR,
# реальні Linux stdout відмови й позитивне відновлення. Не SENS oracle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
timeout 700s bash scripts/test-elfbitscansafe.sh >"$LOG" 2>&1 || {
  tail -n 70 "$LOG" >&2
  exit 1
}
grep -Fq 'BSF-BSR-WRITE-PASS positives=14 closed=14 full=14 recovery=14 machine=CMP-SETE-MOVZX oracle=NOT-RUN energy=NOT-MEASURED' "$LOG"
grep -Fq 'BSF-BSR-ЗАХИСТ-МАШИНА-ГАРАЗД D12=8 ELF64=16 positives=14 zero=2 negatives=6 T5M=byte-exact energy=NOT-MEASURED' "$LOG"
echo 'VERIFIED-BITSCAN-WRITE-PASS fpc=checked machine=16 negatives=6 closed=14 full=14 recovery=14 oracle=NOT-RUN energy=NOT-MEASURED'
