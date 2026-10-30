#!/usr/bin/env bash
# G6.227: машинний low8 Linux exit із pinned D12 та D24-count.
# Штатний PR-агрегатор test-verified-all.sh, без нового FPC runner.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
timeout 300s bash "$ROOT/scripts/test-d12loop.sh"
echo 'VERIFIED-D12LOOP-MASK-PASS checked-FPC=так ELF64=так MOVZX=2'
