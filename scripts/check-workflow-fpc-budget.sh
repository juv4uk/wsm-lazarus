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

# --- Системна перевірка YAML workflow-файлів --------------------------------
# Невалідний YAML не дає жодного job: GitHub створює failure-прогін на кожен
# push (name = шлях файлу, jobs = 0, логи = 404), тож у логах причини не видно
# і дефект живе, доки хтось не прожене workflow вручну.
# Гейт називає такий стан явно. Перевірка лише додає відмову: жодного
# чинного свідка не послаблює і тригерів не змінює.
yaml_rc=0
yaml_report=$(python3 - <<'PY'
import glob, sys

try:
    import yaml
except Exception:
    sys.exit(2)

bad = []
for path in sorted(glob.glob('.github/workflows/*.yml') +
                   glob.glob('.github/workflows/*.yaml')):
    try:
        doc = yaml.safe_load(open(path, encoding='utf-8').read())
    except Exception as exc:
        bad.append('%s: %s' % (path, str(exc).splitlines()[0]))
        continue
    if not isinstance(doc, dict):
        bad.append('%s: верхній рівень не є відображенням YAML' % path)

for line in bad:
    print(line)
sys.exit(1 if bad else 0)
PY
) || yaml_rc=$?
case $yaml_rc in
  0) ;;
  2) echo 'FPC-BUDGET-NOTE PyYAML недоступний — перевірку синтаксису workflow пропущено' >&2 ;;
  *) echo 'FPC-BUDGET-FAIL невалідний YAML workflow (GitHub не запустить жодного job):' >&2
     echo '  типова причина: двокрапка з пробілом у незакавиченому run: — потрібен блоковий скаляр run: |' >&2
     printf '%s\n' "$yaml_report" >&2
     fail=1 ;;
esac

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
  # Анотація для UI й API: без неї у GitHub видно лише 'failure' без причини,
  # і кожен автор PR змушений вивантажувати логи, щоб дізнатися одне слово.
  OFFENDERS=$(printf '%s %s %s' "$push_files" "$pr_files" "$sched_files" | tr -s ' ' | sed 's/^ *//;s/ *$//')
  echo "::error title=FPC-бюджет::перевищено бюджет FPC-workflow (push=$push_count/$PUSH_BUDGET pull_request=$pr_count/$PR_BUDGET schedule_apt=$sched_apt/$NIGHTLY_BUDGET); файли: ${OFFENDERS:-—}; переведіть новий workflow на workflow_dispatch" >&2
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo '## FPC-бюджет перевищено'
      echo
      echo "push=$push_count/$PUSH_BUDGET · pull_request=$pr_count/$PR_BUDGET · schedule_apt=$sched_apt/$NIGHTLY_BUDGET"
      echo
      echo "**Файли:** ${OFFENDERS:-—}"
      echo
      echo 'Виправлення: змінити блок `on:` на `workflow_dispatch` (файли не видаляти).'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  cat >&2 <<'TXT'
FPC-BUDGET-HINT: переведіть новий FPC-workflow на workflow_dispatch або
  нічний schedule (блок on:), або обґрунтуйте зміну бюджету в задачі #805.
  Файли не видаляйте: змінюється лише блок on:.
TXT
  exit 1
fi
echo "FPC-BUDGET-PASS"
