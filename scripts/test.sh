#!/usr/bin/env bash
# M0 headless gate: authority provenance + FPC harness + admitted value mechanics.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
BIN="$BUILD_DIR/bin/wsm-headless"
TEST_BIN="$BUILD_DIR/bin/test-skeleton"
VALUE_TEST_BIN="$BUILD_DIR/bin/test-values"
READER_TEST_BIN="$BUILD_DIR/bin/test-reader"
TEST_UNIT_DIR="$BUILD_DIR/test-units"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-lcl.sh"

# M0.3 value layer must remain mechanism-only: no evaluator/reader/registry
# dependency and no Lisp surface accessor names as exported host API.
if grep -nEi '\b(wsm\.eval|wsm\.reader|semantic-registry)\b' "$ROOT/src/wsm.values.pas"; then
  echo 'VALUES-BOUNDARY-FAIL semantic-layer dependency found in wsm.values.pas' >&2
  exit 1
fi
if grep -nEi '^[[:space:]]*function[[:space:]]+(Car|Cdr)[[:space:]\(]' "$ROOT/src/wsm.values.pas"; then
  echo 'VALUES-BOUNDARY-FAIL surface-named accessor exported from wsm.values.pas' >&2
  exit 1
fi
echo 'VALUES-BOUNDARY-OK mechanism-only structural API'

# M0.4 reader is syntax-only. Semantic registry/evaluator layers must not leak in.
if grep -nEi '\b(wsm\.eval|semantic-registry|semantic[[:space:]_-]*id)\b' "$ROOT/src/wsm.reader.pas"; then
  echo 'READER-BOUNDARY-FAIL semantic-layer dependency found in wsm.reader.pas' >&2
  exit 1
fi
echo 'READER-BOUNDARY-OK syntax-only'

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
"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/tests" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-skeleton \
  "$ROOT/tests/test_skeleton.pas"

test_output=$("$TEST_BIN")
grep -Fxq 'TEST-HARNESS: pass=1 fail=0' <<<"$test_output"

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-values \
  "$ROOT/scripts/test-values.pas"

value_output=$("$VALUE_TEST_BIN")
grep -Eq '^VALUES: pass=[0-9]+ fail=0

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-reader \
  "$ROOT/scripts/test-reader.pas"

reader_output=$("$READER_TEST_BIN")
grep -Eq '^READER: pass=[0-9]+ fail=0

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64 values=green reader=green"
 <<<"$value_output"

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-reader \
  "$ROOT/scripts/test-reader.pas"

reader_output=$("$READER_TEST_BIN")
grep -Eq '^READER: pass=[0-9]+ fail=0
 <<<"$reader_output"

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64 values=green reader=green"
 <<<"$reader_output"

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64 values=green reader=green"
 <<<"$value_output"

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-reader \
  "$ROOT/scripts/test-reader.pas"

reader_output=$("$READER_TEST_BIN")
grep -Eq '^READER: pass=[0-9]+ fail=0
 <<<"$reader_output"

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64 values=green reader=green"
