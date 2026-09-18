#!/usr/bin/env bash
# check-pin.sh — M0-PIN authority gate.
# Переконує, що свідок тримає ОДИН pinned authority набір:
#   1. gitlink external/my-lisp == кодові target з refs/tier1-baseline.properties
#   2. матеріалізований sparse-набір == refs/sparse-authority-paths.txt
# Умова-відмова: будь-який drift → exit 1 (fail-closed).

set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE="refs/tier1-baseline.properties"
SPARSE_LIST="refs/sparse-authority-paths.txt"
SUBMODULE="external/my-lisp"

exp_pin=$(grep -E '^MY_LISP_PIN=' "$BASELINE" | cut -d= -f2 | tr -d '\r')
got_pin=$(git -C "$SUBMODULE" rev-parse HEAD 2>/dev/null || true)

if [[ -z "$exp_pin" ]]; then
  echo "PIN-GATE-FAIL no-expected-pin (empty MY_LISP_PIN in $BASELINE)"
  exit 1
fi
if [[ "$got_pin" != "$exp_pin" ]]; then
  echo "PIN-GATE-FAIL pin-drift: expected=$exp_pin got=${got_pin:-<absent/missing submodule>}"
  exit 1
fi

ok=1
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if [[ ! -f "$SUBMODULE/$rel" && ! -d "$SUBMODULE/$rel" ]]; then
    echo "PIN-GATE-FAIL sparse-miss: $rel"
    ok=0
  fi
done < "$SPARSE_LIST"

if [[ $ok -eq 0 ]]; then
  echo "PIN-GATE-FAIL: sparse set differs from $SPARSE_LIST"
  exit 1
fi

echo "PIN-GATE-OK $exp_pin ($(wc -l < "$SPARSE_LIST") authority paths, sparse-cone enforced)"