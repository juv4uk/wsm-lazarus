#!/usr/bin/env bash
# G6.241 — реальний checked FPC + 8 Linux ELF64 для машинного XOR/OR.
# Вже наявний verified-агрегатор запускає цей профіль без нового workflow,
# додаткового apt, Rust чи Zig. CPU OR не є законом SENS.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v timeout >/dev/null || { echo 'X64-OR-БЛОК: немає timeout' >&2; exit 127; }
timeout 180s bash "$ROOT/scripts/test-x64alu.sh"
echo 'VERIFIED-X64-OR-PASS FPC=checked ELF64=8 T5M=byte-exact energy=NOT-MEASURED'
