#!/usr/bin/env bash
# G6.245 — лише Git entrypoint-права, без SENS семантики або нових збірок.
# Виклик з test-verified-all.sh завжди через bash; цей файл не потребує +x.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Перевіряємо саме Git index: GitHub Actions checkout бере mode із дерева Git,
# а не з chmod, зробленого випадково в робочому каталозі агента.
tracked_executable() {
  local repo=$1 path=$2 stage mode
  stage=$(git -C "$repo" ls-files --stage -- "$path") || return 1
  [[ -n "$stage" && "$stage" != *$'\n'* ]] || return 1
  mode=${stage%% *}
  [[ "$mode" == 100755 && -f "$repo/$path" ]]
}

self_test() {
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  git -C "$tmp" init -q
  mkdir -p "$tmp/scripts"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/scripts/entry.sh"
  chmod 755 "$tmp/scripts/entry.sh"
  git -C "$tmp" add -- scripts/entry.sh
  if ! tracked_executable "$tmp" scripts/entry.sh; then
    echo 'CI-EXECMODES-FAIL позитив: 100755 відхилено' >&2
    return 1
  fi
  chmod 644 "$tmp/scripts/entry.sh"
  git -C "$tmp" add -- scripts/entry.sh
  if tracked_executable "$tmp" scripts/entry.sh; then
    echo 'CI-EXECMODES-FAIL негатив: 100644 прийнято' >&2
    return 1
  fi
  if tracked_executable "$tmp" scripts/unknown.sh; then
    echo 'CI-EXECMODES-FAIL негатив: відсутній шлях прийнято' >&2
    return 1
  fi
  echo 'CI-EXECMODES-самотест позитивів=1 негативів=2'
}

self_test
if [[ ${1:-} == '--самоперевірка' ]]; then
  exit 0
fi

# Тільки ті entrypoint-и, які реально викликаються напряму у
# fpc-headless.yml, scripts/test.sh і scripts/build.sh без `bash`.
# bash-обгорткам +x НЕ потрібний: їх не включено до цієї перевірки.
ENTRYPOINTS=(
  scripts/test.sh
  scripts/sync-authority.sh
  scripts/check-pin.sh
  scripts/check-no-stale-pin-hardcode.sh
  scripts/check-no-lcl.sh
  scripts/build.sh
  scripts/test-bind-cli.sh
  scripts/test-compiler.sh
)

for path in "${ENTRYPOINTS[@]}"; do
  if ! tracked_executable "$ROOT" "$path"; then
    mode=$(git -C "$ROOT" ls-files --stage -- "$path" | awk 'NR==1 {print $1}')
    echo "CI-EXECMODES-FAIL файл=$path git-mode=${mode:-відсутній} очікувано=100755" >&2
    exit 1
  fi
done

echo "CI-EXECMODES-PASS entrypoints=${#ENTRYPOINTS[@]} позитивів=1 негативів=2"
