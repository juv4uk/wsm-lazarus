#!/usr/bin/env bash
# Mechanism-budget growth gate (issue #9): the set of surface names
# wsm.eval.pas actually admits (ResolveAdmittedId calls) must exactly
# match the set documented in docs/mechanism-budget.md's ledger table.
# Fails closed on drift in EITHER direction: an ID added to code
# without ledger justification, or a ledger row for an ID the code
# doesn't actually implement.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVAL_SRC="$ROOT/src/wsm.eval.pas"
LEDGER="$ROOT/docs/mechanism-budget.md"

code_names=$(grep -oE "ResolveAdmittedId\(reg, '[^']+'" "$EVAL_SRC" \
  | sed -E "s/ResolveAdmittedId\(reg, '([^']+)'/\1/" \
  | sort -u)

ledger_names=$(awk -F'|' '
  /^\|[[:space:]]*`[^`]+`[[:space:]]*\|/ {
    gsub(/^[ \t]+|[ \t]+$/, "", $2);
    gsub(/`/, "", $2);
    print $2;
  }
' "$LEDGER" | sort -u)

if [[ "$code_names" != "$ledger_names" ]]; then
  echo "MECHANISM-BUDGET-FAIL admitted IDs in code and ledger disagree" >&2
  echo "--- in code, not in ledger ---" >&2
  comm -23 <(echo "$code_names") <(echo "$ledger_names") >&2
  echo "--- in ledger, not in code ---" >&2
  comm -13 <(echo "$code_names") <(echo "$ledger_names") >&2
  exit 1
fi

count=$(echo "$code_names" | grep -c . || true)
echo "MECHANISM-BUDGET-OK $count admitted IDs, code and ledger agree exactly"
