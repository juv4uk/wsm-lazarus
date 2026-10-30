#!/usr/bin/env bash
# G6.248 — незалежний GNU as проти host ALU: 497 точних машинних команд.
# Чинний verified-агрегатор викликає цей недорогий FPC/binutils gate
# без нового workflow або окремої установки мовних компіляторів.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v timeout >/dev/null || {
  echo 'ALU-AS-БЛОК: немає timeout' >&2; exit 127;
}
timeout 240s bash "$ROOT/scripts/test-x64alu-as.sh"
echo 'VERIFIED-X64ALU-AS-PASS machines=497 bytes=1058 negative=5 energy=NOT-MEASURED'
