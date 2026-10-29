#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$BUILD/units" "$BUILD/bin"
test -f "$ROOT/external/sens/lib/domains/d7.lisp" || {
  echo 'ПОМИЛКА: немає pinned SENS; виконайте scripts/sync-authority.sh' >&2
  exit 2
}
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$BUILD/units" -FE"$BUILD/bin" \
  -otest-bindproektsii "$ROOT/scripts/test-bindproektsii.pas"
timeout 180s "$BUILD/bin/test-bindproektsii" "$ROOT/external/sens"
