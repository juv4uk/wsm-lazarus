#!/usr/bin/env bash
# G6.230 — анотації гейтів: видима причина, а не голий failure.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "ANNOT-OK   $*"; }
bad() { echo "ANNOT-ЗБІЙ $*" >&2; exit 1; }

# 1) Поза GitHub Actions анотації ВИМКНЕНІ (локальні прогони чисті).
# У CI GITHUB_ACTIONS=true уже стоїть у середовищі — тому явно знімаємо,
# інакше перевірка «поза Actions» перевіряла б саме CI.
out=$(env -u GITHUB_ACTIONS -u GITHUB_STEP_SUMMARY bash -c ". '$ROOT/scripts/gh-annotate.sh'; gh_error 't' 'm'" 2>&1)
[ -z "$out" ] && ok "поза Actions — тиша" || bad "локально щось надруковано: $out"

# 2) У Actions — ::error з title і повідомленням.
out=$(GITHUB_ACTIONS=true bash -c ". '$ROOT/scripts/gh-annotate.sh'; gh_error 'pinned SENS authority' 'pin не збігається'" 2>&1)
printf '%s' "$out" | grep -q '::error title=pinned SENS authority::pin не збігається' \
  && ok "є ::error з title і текстом" || bad "немає очікуваної анотації: $out"

# 3) Багаторядкове повідомлення згортається в один рядок (вимога GitHub).
out=$(GITHUB_ACTIONS=true bash -c ". '$ROOT/scripts/gh-annotate.sh'; gh_error 't' 'перший
другий'" 2>&1)
printf '%s' "$out" | grep -q 'перший другий' && ok "багаторядкове згорнуто" || bad "рядки не згорнуто: $out"
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -eq 1 ] && ok "рівно один рядок анотації" || bad "анотація не однорядкова (рядків: $n)"

# 4) Зведення кроку пишеться лише за наявності GITHUB_STEP_SUMMARY.
SUM=$(mktemp); rm -f "$SUM"
GITHUB_ACTIONS=true GITHUB_STEP_SUMMARY="$SUM" bash -c ". '$ROOT/scripts/gh-annotate.sh'; gh_summary '## Причина' '' 'pin не збігається'" >/dev/null 2>&1
[ -s "$SUM" ] && ok "зведення записано" || bad "зведення не записано"
grep -q '## Причина' "$SUM" && ok "зведення містить заголовок" || bad "зведення без заголовка"
rm -f "$SUM"
out=$(GITHUB_ACTIONS=true bash -c ". '$ROOT/scripts/gh-annotate.sh'; gh_summary 'текст'" 2>&1)
[ -z "$out" ] && ok "без STEP_SUMMARY — без помилок" || bad "падіння без STEP_SUMMARY: $out"

# 5) check-pin.sh справді викликає анотацію на відмові.
grep -q 'gh_error' "$ROOT/scripts/check-pin.sh" && ok "check-pin.sh підключено" || bad "check-pin.sh не підключено"

echo "ANNOT-PASS checks=$CHECKS"
