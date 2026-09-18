#!/usr/bin/env bash
# check-pin.sh — M0.1 fail-closed authority gate.
#
# Proves that this checkout uses exactly one pinned my-lisp authority:
#   1. superproject gitlink == canonical MY_LISP_PIN;
#   2. initialized submodule HEAD == that same pin;
#   3. active pin-carrying refs agree with the canonical pin;
#   4. sparse checkout is enabled in non-cone mode;
#   5. materialized submodule file set == sparse-authority-paths.txt.
#
# This validates mechanism/provenance only. It does not define Lisp semantics.

set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE="refs/tier1-baseline.properties"
SPARSE_LIST="refs/sparse-authority-paths.txt"
SUBMODULE="external/my-lisp"
PIN_REFS=(
  "refs/lisp-dependency-manifest.lisp"
  "refs/upstream-dependency-classification.lisp"
)

fail() {
  echo "AUTHORITY-GATE-FAIL $*" >&2
  exit 1
}

expected_pin=$(sed -nE 's/^MY_LISP_PIN=([0-9a-f]{40})$/\1/p' "$BASELINE" | head -n1)
[[ "$expected_pin" =~ ^[0-9a-f]{40}$ ]] || fail "invalid-canonical-pin file=$BASELINE"

read -r gitlink_mode gitlink_type gitlink_pin gitlink_path < <(git ls-tree HEAD "$SUBMODULE")
[[ "$gitlink_mode" == "160000" && "$gitlink_type" == "commit" ]] ||
  fail "not-a-gitlink path=$SUBMODULE mode=${gitlink_mode:-<none>} type=${gitlink_type:-<none>}"
[[ "$gitlink_path" == "$SUBMODULE" ]] ||
  fail "gitlink-path-mismatch expected=$SUBMODULE got=${gitlink_path:-<none>}"
[[ "$gitlink_pin" == "$expected_pin" ]] ||
  fail "superproject-pin-drift expected=$expected_pin got=$gitlink_pin"

[[ -e "$SUBMODULE/.git" ]] || fail "submodule-not-initialized path=$SUBMODULE"
local_pin=$(git -C "$SUBMODULE" rev-parse HEAD 2>/dev/null || true)
[[ "$local_pin" == "$expected_pin" ]] ||
  fail "submodule-head-drift expected=$expected_pin got=${local_pin:-<none>}"

for ref in "${PIN_REFS[@]}"; do
  ref_pin=$(grep -E '^[[:space:]]*\(pin[[:space:]]+\.[[:space:]]+"[0-9a-f]{40}"\)' "$ref" |
    grep -oE '[0-9a-f]{40}' | head -n1 || true)
  [[ "$ref_pin" == "$expected_pin" ]] ||
    fail "ref-pin-drift file=$ref expected=$expected_pin got=${ref_pin:-<none>}"
done

sparse_enabled=$(git -C "$SUBMODULE" config --bool core.sparseCheckout || true)
cone_enabled=$(git -C "$SUBMODULE" config --bool core.sparseCheckoutCone || true)
[[ "$sparse_enabled" == "true" ]] || fail "sparse-checkout-disabled path=$SUBMODULE"
[[ "$cone_enabled" == "false" ]] || fail "sparse-cone-not-disabled got=${cone_enabled:-<unset>}"

expected_files=$(mktemp)
actual_files=$(mktemp)
trap 'rm -f "$expected_files" "$actual_files"' EXIT

sed -e 's/\r$//' -e '/^[[:space:]]*$/d' "$SPARSE_LIST" | LC_ALL=C sort -u > "$expected_files"
find "$SUBMODULE" -type f ! -path "$SUBMODULE/.git" -printf '%P\n' | LC_ALL=C sort -u > "$actual_files"

if ! diff -u "$expected_files" "$actual_files" >/dev/null; then
  echo "AUTHORITY-GATE-FAIL materialized-set-drift" >&2
  diff -u "$expected_files" "$actual_files" >&2 || true
  exit 1
fi

count=$(wc -l < "$expected_files" | tr -d ' ')
echo "AUTHORITY-GATE-OK pin=$expected_pin files=$count sparse=non-cone exact-set=true"
