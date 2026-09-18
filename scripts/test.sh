#!/usr/bin/env bash
# M0.2 gate: authority provenance + headless FPC harness only.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
BIN="$BUILD_DIR/bin/wsm-headless"
TEST_BIN="$BUILD_DIR/bin/test-skeleton"
TEST_UNIT_DIR="$BUILD_DIR/test-units"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-lcl.sh"
"$ROOT/scripts/build.sh"

version_output=$("$BIN" --version)
grep -Fxq 'WSM-LAZARUS-HEADLESS version=0.0.0-m0.2' <<<"$version_output"
grep -Fxq 'FPC-BASELINE >=3.2.2' <<<"$version_output"

self_test_output=$("$BIN" --self-test)
[[ "$self_test_output" == 'HEADLESS-HARNESS-OK' ]] || {
  echo "TEST-FAIL self-test-output=$self_test_output" >&2
  exit 1
}

set +e
"$BIN" --not-a-command >/dev/null 2>&1
usage_rc=$?
set -e
[[ $usage_rc -eq 64 ]] || {
  echo "TEST-FAIL usage-exit expected=64 got=$usage_rc" >&2
  exit 1
}

mkdir -p "$TEST_UNIT_DIR"
"$FPC_BIN"   -B   -Mobjfpc   -O1   -Fu"$ROOT/tests"   -FU"$TEST_UNIT_DIR"   -FE"$BUILD_DIR/bin"   -otest-skeleton   "$ROOT/tests/test_skeleton.pas"

test_output=$("$TEST_BIN")
grep -Fxq 'TEST-HARNESS: pass=1 fail=0' <<<"$test_output"

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64"
