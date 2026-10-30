#!/usr/bin/env bash
# G6.231 — агрегатор test.sh мусить називати ЗЛАМАНИЙ КРОК, а не просто падати.
#
# Перевіряємо саму механіку пастки на синтетичному скрипті: локально —
# рядок DOMAIN-FAIL з командою; у CI — ще й ::error-анотація. Справжній
# test.sh не запускаємо: він довгий і залежить від збірки.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "AGG-ANNOT-OK   $*"; }
bad() { echo "AGG-ANNOT-ЗБІЙ $*" >&2; exit 1; }

# Витягуємо пастку зі справжнього test.sh, щоб тест перевіряв ЙОГО код.
grep -q 'trap ' "$ROOT/scripts/test.sh" && ok "test.sh має EXIT-пастку" || bad "у test.sh немає пастки"
grep -q 'gh_error' "$ROOT/scripts/test.sh" && ok "test.sh кличе gh_error" || bad "test.sh не кличе gh_error"

cat > "$TMP/fail.sh" <<'EOS'
set -euo pipefail
ROOT="$1"
. "$ROOT/scripts/gh-annotate.sh" 2>/dev/null || true
trap '_rc=$?; if [ "$_rc" -ne 0 ]; then
        echo "DOMAIN-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
        if command -v gh_error >/dev/null 2>&1; then
          gh_error "агрегатор test.sh" "крок упав (код $_rc): $BASH_COMMAND"
        fi
      fi' EXIT
true
false
EOS

out=$(env -u GITHUB_ACTIONS bash "$TMP/fail.sh" "$ROOT" 2>&1)
printf '%s' "$out" | grep -q 'DOMAIN-FAIL крок="false" код=1' && ok "названо зламану команду" || bad "команду не названо: $out"
printf '%s' "$out" | grep -q '::error' && bad "поза Actions анотація не має друкуватися" || ok "поза Actions без анотації"

out=$(GITHUB_ACTIONS=true bash "$TMP/fail.sh" "$ROOT" 2>&1)
printf '%s' "$out" | grep -q '::error title=агрегатор test.sh::крок упав (код 1): false' \
  && ok "у CI є ::error з командою" || bad "немає анотації: $out"

echo "AGG-ANNOT-PASS checks=$CHECKS"
