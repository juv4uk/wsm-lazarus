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
SID8_INTEGRITY_TEST_BIN="$BUILD_DIR/bin/test-sid8-integrity"
TEST_UNIT_DIR="$BUILD_DIR/test-units"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-lcl.sh"
"$ROOT/scripts/check-mechanism-budget.sh"
"$ROOT/scripts/check-sid8-opaque.sh"

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
# "в ньому неможливо 00000000-11111111 визначити як функції нашої мови
# [без лапок/літералів]"). Pascal has no equivalent of Rust's
# `sid!(00000001)` bare-token compile-time macro; a raw numeric literal
# silently collapses width at the lexer, and a quoted string handed to
# a validator still requires writing a bit-pattern-shaped spelling
# directly into this file. So this file contains NEITHER: its eight
# admitted identities are resolved by ordinary surface name
# (RegistryLookup(reg, 'quote', ...) etc., in EvalContextInit) against
# the caller's pinned registry -- the same path every interpreted
# expression's own operator already goes through. No eight-bit-shaped
# literal, quoted or bare, may exist anywhere in this file at all.
if grep -nE "'[01]{8}'|%[01]{8}" "$ROOT/src/wsm.eval.pas"; then
  echo 'EVAL-BOUNDARY-FAIL a bit-pattern-shaped literal (quoted or bare) exists in wsm.eval.pas -- identities must be resolved by name, not hardcoded' >&2
  exit 1
fi
if ! grep -nE "ResolveAdmittedId\(reg, '(quote|cons|car|cdr|cond|lambda|-|=)', ctx\.Id" "$ROOT/src/wsm.eval.pas" >/dev/null; then
  echo 'EVAL-BOUNDARY-FAIL no by-name admitted-identity resolution found in wsm.eval.pas' >&2
  exit 1
fi
echo 'EVAL-BOUNDARY-OK id-dispatch-only (opaque TSid8, resolved by name via RegistryLookup, no hardcoded bit-pattern anywhere)'

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

"$FPC_BIN" \
  -B \
  -Mobjfpc \
  -O1 \
  -Fu"$ROOT/src" \
  -FU"$TEST_UNIT_DIR" \
  -FE"$BUILD_DIR/bin" \
  -otest-sid8-integrity \
  "$ROOT/scripts/test-sid8-integrity.pas"

sid8_integrity_output=$(cd "$ROOT" && "$SID8_INTEGRITY_TEST_BIN")
grep -Eq '^SID8-INTEGRITY: pass=[0-9]+ fail=0$' <<<"$sid8_integrity_output"

echo "HEADLESS-TEST-OK version=0.0.0-m0.2 usage-exit=64 values=green reader=green registry=green eval=green sid8-integrity=green"
