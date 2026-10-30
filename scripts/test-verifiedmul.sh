#!/usr/bin/env bash
# G6.199 — швидкий FPC build і справжній x86-64 ELF64; без Rust/Zig.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VM-БЛОК: немає fpc' >&2; exit 127; }
test -f "$ROOT/external/sens/lib/domains/d5.lisp" || {
  echo 'VM-БЛОК: не синхронізовано pinned SENS' >&2
  exit 66
}
mkdir -p build/vm-units build/vm-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vm-units" \
  -FE"$ROOT/build/vm-bin" -otest-verifiedmul \
  "$ROOT/scripts/test-verifiedmul.pas"
"$ROOT/build/vm-bin/test-verifiedmul" "$ROOT/external/sens"
