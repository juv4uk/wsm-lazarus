#!/usr/bin/env bash
# G6.157 (задача #805) — бюджет workflow, що ставлять fp-compiler на push/pull_request.
#
# Вимога власника: FPC-встановлення не має розповзатися назад на кожен push
# і кожен PR. Після скорочення лишається рівно:
#   push          — 1 workflow (core1-repl.yml), це збірка+REPL на main;
#   pull_request  — 2 workflow (fpc-headless.yml — збірка, core1-repl.yml — семантика через REPL).
# Решта FPC-workflow живуть на нічному schedule або workflow_dispatch.
#
# Гейт закритий за замовчуванням: будь-який новий (або повернутий) тригер
# push/pull_request у файлі, що встановлює fp-compiler, валить перевірку.
# Нових workflow цей скрипт не створює і нічого не вимикає — лише рахує.
set -euo pipefail

cd "$(dirname "$0")/.."

PUSH_BUDGET="${FPC_BUDGET_PUSH:-1}"
PR_BUDGET="${FPC_BUDGET_PR:-3}"
# Бюджет нічного пакета: скільки workflow ще ставлять fp-compiler через apt
# безумовно (без спільного кеша). Задача #805: 248 -> 178.
NIGHTLY_BUDGET="${FPC_BUDGET_NIGHTLY_APT:-178}"
# Дозволений мінімум: єдине джерело істини для гейта.
ALLOW_PUSH="core1-repl.yml"
ALLOW_PR="core1-repl.yml fpc-headless.yml wide-pipe-stdin-memory.yml"
# wide-pipe-stdin-memory.yml доданий у бюджет PR (G6.200): тригер фільтрується
# шляхами (src/senswidepotikelf.lpr, scripts/test-widepotikelf.sh, external/sens)
# і запускає лише вже наявні native-тести. Бюджет розширено з 2 до 3 свідомо:
# альтернатива — зняти pull_request і тим вимкнути перевірку, а це заборонено.

push_count=0
pr_count=0
push_files=""
pr_files=""
sched_count=0
sched_apt=0
sched_cached=0
sched_files=""

# Ключі другого рівня всередині блоку on: (до першого рядка без відступу).
triggers() {
  awk '
    /^on:[[:space:]]*$/ { inon = 1; next }
    inon && /^[^[:space:]#]/ { inon = 0 }
    inon && /^  [A-Za-z_]+:/ {
      k = $0
      sub(/^  /, "", k)
      sub(/:.*$/, "", k)
      print k
    }
    inon && /^on:[[:space:]]*[^[:space:]]/ { print "INLINE" }
  ' "$1"
}

for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -e "$f" ] || continue
  # Рахуємо лише ті workflow, що справді встановлюють fp-compiler.
  grep -q 'fp-compiler' "$f" || continue
  t=$(triggers "$f" || true)
  base=$(basename "$f")
  case $'\n'"$t"$'\n' in
    *$'\npush\n'*)
      push_count=$((push_count + 1))
      case " $ALLOW_PUSH " in *" $base "*) ;; *) push_files="$push_files $f" ;; esac
      ;;
  esac
  case $'\n'"$t"$'\n' in
    *$'\npull_request\n'*)
      pr_count=$((pr_count + 1))
      case " $ALLOW_PR " in *" $base "*) ;; *) pr_files="$pr_files $f" ;; esac
      ;;
  esac
  case $'\n'"$t"$'\n' in
    *$'\nschedule\n'*)
      sched_count=$((sched_count + 1))
      # "кешований" = встановлення йде через scripts/fpc-restore.sh, тобто
      # apt-get install виконується лише за холодного кеша, а не щоночі.
      if grep -q 'scripts/fpc-restore.sh' "$f"; then
        sched_cached=$((sched_cached + 1))
      else
        sched_apt=$((sched_apt + 1))
        sched_files="$sched_files $f"
      fi
      ;;
  esac
done

total=$(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | wc -l | tr -d ' ')

echo "FPC-BUDGET workflows=$total push=$push_count/$PUSH_BUDGET pull_request=$pr_count/$PR_BUDGET schedule=$sched_count schedule_apt=$sched_apt/$NIGHTLY_BUDGET schedule_cached=$sched_cached"

fail=0
if [ -n "$push_files" ] || [ "$push_count" -gt "$PUSH_BUDGET" ]; then
  echo "FPC-BUDGET-FAIL на push понад бюджет ($push_count > $PUSH_BUDGET):" >&2
  for f in $push_files; do echo "  $f" >&2; done
  fail=1
fi
if [ -n "$pr_files" ] || [ "$pr_count" -gt "$PR_BUDGET" ]; then
  echo "FPC-BUDGET-FAIL на pull_request понад бюджет ($pr_count > $PR_BUDGET):" >&2
  for f in $pr_files; do echo "  $f" >&2; done
  fail=1
fi
if [ "$sched_apt" -gt "$NIGHTLY_BUDGET" ]; then
  echo "FPC-BUDGET-FAIL нічних безумовних apt-встановлень більше бюджету ($sched_apt > $NIGHTLY_BUDGET):" >&2
  for f in $sched_files; do echo "  $f" >&2; done
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  cat >&2 <<'TXT'
FPC-BUDGET-HINT: переведіть новий FPC-workflow на workflow_dispatch або
  нічний schedule (блок on:), або обґрунтуйте зміну бюджету в задачі #805.
  Файли не видаляйте: змінюється лише блок on:.
TXT
  exit 1
fi
echo "FPC-BUDGET-PASS"
