#!/usr/bin/env bash
# G6.243 — скрипт, який викликають як ./scripts/X.sh, мусить бути виконуваним.
#
# Навіщо: 30.10 `scripts/test.sh` втратив біт 100755, і m0-headless почав
# падати з `./scripts/test.sh: Permission denied` (код 126) — тобто ЧЕРВОНИМ
# став кожен PR, незалежно від його змісту.
#
# Перевіряємо лише те, що справді ламається: файли, які workflow запускає
# напряму (./scripts/...), а не через `bash script.sh` — там біт не потрібен.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
checked=0
seen=""
for wf in .github/workflows/*.yml; do
  [ -e "$wf" ] || continue
  for path in $(grep -ohE '\./scripts/[A-Za-z0-9_./-]+\.sh' "$wf" | sort -u); do
    rel=${path#./}
    case " $seen " in *" $rel "*) continue ;; esac
    seen="$seen $rel"
    checked=$((checked+1))
    if [ ! -e "$rel" ]; then
      echo "EXEC-BITS-FAIL $wf викликає $rel, а файла немає" >&2
      fail=1
      continue
    fi
    mode=$(git ls-files -s "$rel" | awk '{print $1}')
    if [ "$mode" != "100755" ]; then
      echo "EXEC-BITS-FAIL $rel має режим ${mode:-<невідомо>}, а викликається як $path" >&2
      fail=1
      continue
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=права на скрипти::workflow викликає ./scripts/X.sh, а файл не виконуваний (потрібен 100755)" >&2
  fi
  echo "виправлення: git update-index --chmod=+x <файл> і закомітити" >&2
  exit 1
fi
echo "EXEC-BITS-PASS перевірено=$checked"
