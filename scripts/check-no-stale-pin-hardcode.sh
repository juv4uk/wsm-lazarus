#!/usr/bin/env bash
# Заборона застарілого hardcode піна 1f1bf676eeac605e… у scripts/.
# Чинний пін — тільки MY_LISP_PIN / gitlink external/sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
STALE=1f1bf676eeac605e065035d9dd2adaae807f1788
HITS=$(mktemp)
trap 'rm -f "$HITS"' EXIT
# Лише контрольовані скрипти: docs/evidence можуть фіксувати історичний SHA.
git ls-files 'scripts/*.sh' 'scripts/**/*.sh' 2>/dev/null | while read -r f; do
  [[ -f "$f" ]] || continue
  [[ "$f" == *check-no-stale-pin-hardcode.sh ]] && continue
  if grep -nF "$STALE" "$f" >/dev/null 2>&1; then
    # fallback-only у if [[ -z ]] дозволено лише як не-equality default? — ні:
    # будь-який hardcode старого SHA у scripts ламає майбутній pin bump.
    grep -nF "$STALE" "$f" | sed "s|^|$f:|" >>"$HITS" || true
  fi
done
if [[ -s "$HITS" ]]; then
  echo 'STALE-PIN-HARDCODE: scripts містять застарілий 1f1bf676…' >&2
  cat "$HITS" >&2
  echo 'Замініть на: PIN=$(git -C external/sens rev-parse HEAD) або MY_LISP_PIN' >&2
  exit 1
fi
echo 'STALE-PIN-HARDCODE-OK scripts=clean'
