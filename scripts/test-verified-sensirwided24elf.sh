#!/usr/bin/env bash
# G6.261 — підключити справжню FPC команду до чинного verified-all.
# Жодного окремого workflow, apt чи збірки Rust на кожен push.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
timeout 550s bash scripts/test-sensirwided24elf.sh >"$LOG" 2>&1 || {
  tail -n 95 "$LOG" >&2
  exit 1
}
grep -Fxq 'D24-КОМАНДА-ГОТОВО FPC=checked physical-source=10 ELF64=10 negative=8 no-clobber=2 recovery=1 deterministic=1 T5M=exact oracle=NOT-RUN energy=NOT-MEASURED' "$LOG"
echo 'VERIFIED-D24-COMMAND-PASS FPC=checked physical-source=10 ELF64=10 negative=8 no-clobber=2 recovery=1 deterministic=1 T5M=exact oracle=NOT-RUN energy=NOT-MEASURED'
