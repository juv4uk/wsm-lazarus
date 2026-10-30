#!/usr/bin/env bash
# G6.245: дешевий регресійний свідок прав безпосереднього запуску CI-сценаріїв.
# Перевіряємо режими саме в Git-індексі: чистий checkout має працювати без chmod.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Тільки файли, які викликають як програму, а не через bash <файл>.
# fpc-headless.yml запускає sync-authority.sh і test.sh безпосередньо;
# test.sh безпосередньо викликає наведені нижче три guard-и.
required=(
  scripts/sync-authority.sh
  scripts/test.sh
  scripts/check-pin.sh
  scripts/check-no-stale-pin-hardcode.sh
  scripts/check-no-lcl.sh
)
failed=0
for path in "${required[@]}"; do
  entry=$(git ls-files --stage -- "$path")
  if [[ -z "$entry" ]]; then
    printf 'ПРАВА-ЗАПУСКУ-ЗБІЙ: файл не відстежується: %s\n' "$path" >&2
    failed=1
    continue
  fi
  mode=${entry%% *}
  if [[ "$mode" != 100755 ]]; then
    printf 'ПРАВА-ЗАПУСКУ-ЗБІЙ: %s має git mode=%s, потрібно 100755\n' "$path" "$mode" >&2
    failed=1
  fi
done
if (( failed )); then
  echo 'VERIFIED-EXECMODE-FAIL' >&2
  exit 1
fi
printf 'VERIFIED-EXECMODE-PASS files=%d\n' "${#required[@]}"
