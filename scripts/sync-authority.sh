#!/usr/bin/env bash
# sync-authority.sh — materialize only the pinned my-lisp authority slice.
#
# The superproject gitlink and refs/tier1-baseline.properties must already agree.
# This command never chooses a newer upstream revision on its own.

set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE="refs/tier1-baseline.properties"
SPARSE_LIST="refs/sparse-authority-paths.txt"
SUBMODULE="external/my-lisp"

fail() {
  echo "AUTHORITY-SYNC-FAIL $*" >&2
  exit 1
}

expected_pin=$(sed -nE 's/^MY_LISP_PIN=([0-9a-f]{40})$/\1/p' "$BASELINE" | head -n1)
[[ "$expected_pin" =~ ^[0-9a-f]{40}$ ]] || fail "invalid-canonical-pin file=$BASELINE"

read -r gitlink_mode gitlink_type gitlink_pin gitlink_path < <(git ls-tree HEAD "$SUBMODULE")
[[ "$gitlink_mode" == "160000" && "$gitlink_type" == "commit" ]] ||
  fail "not-a-gitlink path=$SUBMODULE"
[[ "$gitlink_path" == "$SUBMODULE" ]] ||
  fail "gitlink-path-mismatch expected=$SUBMODULE got=${gitlink_path:-<none>}"
[[ "$gitlink_pin" == "$expected_pin" ]] ||
  fail "superproject-pin-drift expected=$expected_pin got=$gitlink_pin"

git submodule update --init --filter=blob:none "$SUBMODULE"

local_pin=$(git -C "$SUBMODULE" rev-parse HEAD)
[[ "$local_pin" == "$expected_pin" ]] ||
  fail "submodule-head-drift expected=$expected_pin got=$local_pin"

git -C "$SUBMODULE" sparse-checkout init --no-cone

# Anchor every authority path at repository root. The source list stays a
# plain path inventory; sparse-checkout receives gitignore-style exact patterns.
sed -e 's/\r$//' -e '/^[[:space:]]*$/d' -e 's#^#/#' "$SPARSE_LIST" |
  git -C "$SUBMODULE" sparse-checkout set --no-cone --stdin

git -C "$SUBMODULE" checkout --detach "$expected_pin" >/dev/null

./scripts/check-pin.sh

echo "AUTHORITY-SYNC-OK pin=$expected_pin"
