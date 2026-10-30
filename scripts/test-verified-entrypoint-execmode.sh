#!/usr/bin/env bash
# G6/CI — захист Git execute-mode двох наявних CI entrypoint.
# Цей тест перевіряє ТІЛЬКИ host git tree, не закони SENS чи Dn.
# Дані: git index (borrowed), позитивні й негативні тимчасові індекси.
# Питання: чому chmod робочого дерева не достатній? Чому 100755 потрібен
# у коміті? Чому зміни режиму не повинні змінювати blob SHA?
# Чому ці помилки мають бути відхилені до запуску дорогого FPC?
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v git >/dev/null || { echo 'ENTRYPOINT-EXECMODE-БЛОК: git' >&2; exit 127; }
command -v mktemp >/dev/null || { echo 'ENTRYPOINT-EXECMODE-БЛОК: mktemp' >&2; exit 127; }

# Прямо виконувані у спільних CI shell gate, НЕ всі .sh у репозиторії:
# скрипти через «bash path.sh» не вимагають executable-біта.
ENTRYPOINTS=(
  scripts/test.sh
  scripts/check-no-stale-pin-hardcode.sh
)

check_modes() {
  local repo=$1 path record mode
  for path in "${ENTRYPOINTS[@]}"; do
    record=$(git -C "$repo" ls-files --stage -- "$path") || {
      echo "ENTRYPOINT-EXECMODE-FAIL: не вдалося прочитати git index: $path" >&2
      return 1
    }
    if [[ -z "$record" ]]; then
      echo "ENTRYPOINT-EXECMODE-FAIL: немає у git index: $path" >&2
      return 1
    fi
    mode=${record%% *}
    if [[ "$mode" != 100755 ]]; then
      echo "ENTRYPOINT-EXECMODE-FAIL: $path має git mode=$mode, потрібен 100755" >&2
      return 1
    fi
  done
}

check_modes "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
mkdir -p "$TMP/scripts"
for path in "${ENTRYPOINTS[@]}"; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/$path"
  chmod 755 "$TMP/$path"
done
git -C "$TMP" add -- "${ENTRYPOINTS[@]}"
check_modes "$TMP"

NEGATIVE=0
RECOVERY=0
for path in "${ENTRYPOINTS[@]}"; do
  # Симуляція випадкової зміни лише MODE у Git, без зміни байтів файлу.
  before=$(git -C "$TMP" ls-files --stage -- "$path")
  blob_before=$(printf '%s' "$before" | awk '{print $2}')
  git -C "$TMP" update-index --chmod=-x -- "$path"
  if check_modes "$TMP" >"$TMP/reject.out" 2>"$TMP/reject.err"; then
    echo "ENTRYPOINT-EXECMODE-FAIL: режим 100644 пройшов: $path" >&2
    exit 1
  fi
  grep -Fq "ENTRYPOINT-EXECMODE-FAIL: $path має git mode=100644" "$TMP/reject.err"
  NEGATIVE=$((NEGATIVE+1))
  git -C "$TMP" update-index --chmod=+x -- "$path"
  after=$(git -C "$TMP" ls-files --stage -- "$path")
  blob_after=$(printf '%s' "$after" | awk '{print $2}')
  [[ "$blob_before" == "$blob_after" ]] || {
    echo "ENTRYPOINT-EXECMODE-FAIL: тест змінив blob $path" >&2; exit 1;
  }
  check_modes "$TMP"
  RECOVERY=$((RECOVERY+1))
done
[[ "$NEGATIVE" -eq 2 && "$RECOVERY" -eq 2 ]]
echo "VERIFIED-ENTRYPOINT-EXECMODE-PASS paths=2 negatives=$NEGATIVE recovery=$RECOVERY"
