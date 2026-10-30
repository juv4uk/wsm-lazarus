#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
exec timeout 1800s python3 scripts/energy/quot-runtime-benchmark.py "$@"
