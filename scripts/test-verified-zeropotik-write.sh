#!/usr/bin/env bash
# G6.223: штатний PR FPC runner перевіряє справжні T5M/ELF та
# Linux stdout fail-closed без нового workflow чи встановлення Rust/Zig.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
timeout 300s bash "$ROOT/scripts/test-elfd12zeropotik.sh"
echo "VERIFIED-ZEROPOTIK-WRITE-PASS checked-FPC=так stdout-fail-closed=так"
