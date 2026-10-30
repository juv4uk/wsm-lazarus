#!/usr/bin/env bash
# G6.211 — АГРЕГАТОР усіх перевірок «одноразовий перевірений контекст».
#
# Навіщо: кожен новий verified-профіль отримував власний workflow, а бюджет
# власника (scripts/check-workflow-fpc-budget.sh) не дозволяє додавати
# fp-compiler у pull_request. Через це тести існували, але на PR не бігли.
# Тепер вони виконуються ОДНИМ кроком у вже наявному FPC-прогоні:
# жодного нового apt, жодного нового workflow.
#
# Кожен скрипт запускається окремо; невдача будь-якого валить агрегатор.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

FAILED=""
RAN=0
SKIPPED=""

# Лише ФАЙЛИ ПІД КОНТРОЛЕМ ВЕРСІЙ: локальні чернетки не мають валити CI.
for s in $(git ls-files 'scripts/test-verified*.sh'); do
  [ -e "$s" ] || continue
  case "$(basename "$s")" in
    test-verified-all.sh) continue ;;
  esac
  # Скрипти, що потребують окремих даних або є репродукціями ручних сесій,
  # позначаються в шапці словом ВИКЛЮЧЕНО-З-АГРЕГАТОРА.
  if head -12 "$s" | grep -q "ВИКЛЮЧЕНО-З-АГРЕГАТОРА"; then
    SKIPPED="$SKIPPED $(basename "$s")"
    continue
  fi
  RAN=$((RAN+1))
  printf 'VERIFIED-ALL → %s\n' "$(basename "$s")"
  if ! bash "$s" >/tmp/va-$$.log 2>&1; then
    printf 'VERIFIED-ALL-ЗБІЙ %s\n' "$(basename "$s")"
    tail -20 /tmp/va-$$.log
    FAILED="$FAILED $(basename "$s")"
  else
    grep -E '\-PASS' /tmp/va-$$.log | tail -1 || true
  fi
  rm -f /tmp/va-$$.log
done

printf 'VERIFIED-ALL запущено=%d пропущено=[%s] збоїв=[%s]\n' "$RAN" "$SKIPPED" "$FAILED"
if [ -n "$FAILED" ]; then
  echo "VERIFIED-ALL-FAIL"
  exit 1
fi
echo "VERIFIED-ALL-PASS"
