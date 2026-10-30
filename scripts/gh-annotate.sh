#!/usr/bin/env bash
# G6.230 — СПІЛЬНА анотація для GitHub Actions.
#
# Навіщо: гейти проєкту (check-pin.sh, test.sh, check-workflow-fpc-budget.sh)
# друкують причину у stderr, але в UI й через API видно лише
# conclusion=failure з порожнім output. Через це діагноз коштує
# вивантаження логів кроку — саме так три PR цього сеансу з'їли два проходи.
#
# Використання (з іншого скрипта):
#   . "$(dirname "$0")/gh-annotate.sh"
#   gh_error "AUTHORITY-GATE" "pin не збігається: очікували X, маємо Y"
#
# Поза GitHub Actions нічого зайвого не друкує: без GITHUB_ACTIONS=true
# анотації вимкнені, щоб локальні прогони лишалися чистими.

gh_annotate_enabled() {
  [ "${GITHUB_ACTIONS:-}" = "true" ]
}

# gh_error <title> <message...>
gh_error() {
  local title="$1"; shift
  local msg="$*"
  gh_annotate_enabled || return 0
  # Однорядковий варіант: GitHub не приймає сирих переводів рядка в анотації.
  printf '::error title=%s::%s\n' "$title" "$(printf '%s' "$msg" | tr '\n' ' ' | sed 's/  */ /g')" >&2
}

# gh_summary <markdown...> — зведення кроку (видно на сторінці прогону).
gh_summary() {
  gh_annotate_enabled || return 0
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
}
