#!/usr/bin/env bash
# M0 headless gate: authority provenance + FPC harness + admitted value/reader mechanics.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
BIN="$BUILD_DIR/bin/wsm-headless"
TEST_BIN="$BUILD_DIR/bin/test-skeleton"
VALUE_TEST_BIN="$BUILD_DIR/bin/test-values"
READER_TEST_BIN="$BUILD_DIR/bin/test-reader"
REGISTRY_TEST_BIN="$BUILD_DIR/bin/test-registry"
EVAL_TEST_BIN="$BUILD_DIR/bin/test-eval"
TEST_UNIT_DIR="$BUILD_DIR/test-units"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-lcl.sh"

# M0.3 value layer: mechanism only.
if grep -nEi '\b(wsm\.eval|wsm\.reader|semantic-registry)\b' "$ROOT/src/wsm.values.pas"; then
  echo 'VALUES-BOUNDARY-FAIL semantic-layer dependency found in wsm.values.pas' >&2
  exit 1
fi
if grep -nEi '^[[:space:]]*function[[:space:]]+(Car|Cdr)[[:space:]\(]' "$ROOT/src/wsm.values.pas"; then
  echo 'VALUES-BOUNDARY-FAIL surface-named accessor exported from wsm.values.pas' >&2
  exit 1
fi

# Concrete pair layout and generic equality must not be public host API.
if sed -n '/^interface$/,/^implementation$/p' "$ROOT/src/wsm.values.pas" |
   grep -nE '\b(PPair|TPair|ValueEqual)\b'; then
  echo 'VALUES-BOUNDARY-FAIL pair layout or generic equality leaked through interface' >&2
  exit 1
fi

# Downstream units may carry the opaque TValue.pair handle, but may not know
# its concrete PPair/TPair layout or dereference/mutate it.
if grep -R -nE '\b(PPair|TPair)\b|\.pair\^|\^\.(head|tail)'      "$ROOT/src" "$ROOT/scripts" "$ROOT/tests"      --include='*.pas' --include='*.lpr' |
   grep -v '/wsm.values.pas:'; then
  echo 'VALUES-BOUNDARY-FAIL downstream pair-layout knowledge found' >&2
  exit 1
fi

echo 'VALUES-BOUNDARY-OK mechanism-only opaque structural API'

# M0.4 reader: syntax only.
if grep -nEi '\b(wsm\.eval|semantic-registry|semantic[[:space:]_-]*id)\b' "$ROOT/src/wsm.reader.pas"; then
  echo 'READER-BOUNDARY-FAIL semantic-layer dependency found in wsm.reader.pas' >&2
  exit 1
fi
echo 'READER-BOUNDARY-OK syntax-only'

# M0.5 semantic registry bridge: identity mapping only, no evaluator
# dependency, and no hand-copied second-authority ID->meaning table
# (#7's own "не копіювати semantic registry as Pascal enum").
if sed -n '/^uses$/,/;/p' "$ROOT/src/wsm.registry.pas" | grep -nEi '\bwsm\.eval\b'; then
  echo 'REGISTRY-BOUNDARY-FAIL evaluator dependency found in wsm.registry.pas uses clause' >&2
  exit 1
fi
if grep -nE "'[01]{8}'" "$ROOT/src/wsm.registry.pas"; then
  echo 'REGISTRY-BOUNDARY-FAIL hardcoded/string semantic-ID literal found in wsm.registry.pas' >&2
  exit 1
fi
echo 'REGISTRY-BOUNDARY-OK identity-mapping-only, no hand-copied authority'

# M0.6 evaluator skeleton: semantic-ID dispatch only, never an
# operator-spelling switch (#8's own "не додавати fallback 'якщо ID
# невідомий — подивитися ім'я'"). The only place an operator spelling
# may appear at all is as the dynamic input to RegistryLookup itself
# (SymbolName(head), taken from whatever expression is being evaluated)
# -- never as a literal compared against for control flow.
if grep -nE "=[[:space:]]*'(quote|cond|lambda|cons|car|cdr)'" "$ROOT/src/wsm.eval.pas"; then
  echo 'EVAL-BOUNDARY-FAIL operator-spelling comparison found in wsm.eval.pas' >&2
  exit 1
fi

# SID8-ONLY (issue #24, ecosystem#16, 2026-09-23 -- owner correction:
# a bare `TSid8 = Byte` alias is itself a forbidden substitution, since
# FPC cannot distinguish a validated identity from an arbitrary number
# of the same value). TSid8 is now an opaque record whose only
# constructor, TSid8.FromExact, validates the full eight-character
# spelling unconditionally on every construction (wsm.registry.pas).
# Dispatch itself (opID = ID_QUOTE, etc.) is TSid8's overloaded `=`,
# never a raw string comparison. A quoted '00000001'-style string may
# ONLY appear as FromExact(...) construction input (the human-facing
# surface before resolution) -- never as an operand compared directly
# for control flow.
if grep -nE "(=|<>)[[:space:]]*'[01]{8}'|'[01]{8}'[[:space:]]*(=|<>)" "$ROOT/src/wsm.eval.pas" | grep -v "FromExact('[01]\{8\}')"; then
  echo 'EVAL-BOUNDARY-FAIL quoted-string SID compared for dispatch in wsm.eval.pas (SID8-ONLY forbids string identity)' >&2
  exit 1
fi
if ! grep -nE "TSid8\.FromExact\('[01]{8}'\)" "$ROOT/src/wsm.eval.pas" >/dev/null; then
  echo 'EVAL-BOUNDARY-FAIL no TSid8.FromExact(...) validated ID construction found in wsm.eval.pas' >&2
  exit 1
fi
echo 'EVAL-BOUNDARY-OK id-dispatch-only (opaque TSid8, validated construction), no operator-name switch, no string SID'

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
grep -Eq '^VALUES: pass=[0-9]+ fail=0$' <<<"$value_output"

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
grep -Eq '^READER: pass=[0-9]+ fail=0$' <<<"$reader_output"

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-registry \
  "$ROOT/scripts/test-registry.pas"

registry_output=$(cd "$ROOT" && "$REGISTRY_TEST_BIN")
grep -Eq '^REGISTRY: pass=[0-9]+ fail=0$' <<<"$registry_output"

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-eval \
  "$ROOT/scripts/test-eval.pas"

eval_output=$(cd "$ROOT" && "$EVAL_TEST_BIN")
grep -Eq '^EVAL: pass=[0-9]+ fail=0$' <<<"$eval_output"

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64 values=green reader=green registry=green eval=green"
