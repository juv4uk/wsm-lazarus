#!/usr/bin/env bash
# G6.156 — гейт проти безумовного встановлення FPC у кожному прогоні.
# Вимога власника: не витрачати енергію на важкі/повторні встановлення.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
total=$(ls .github/workflows/*.yml | wc -l)
guarded=$(grep -l "command -v fpc" .github/workflows/*.yml | wc -l)
# «Безумовне» = встановлює ЛИШЕ fp-compiler/git, але без захисту.
# Рядки з lazarus/xvfb/binutils захищати не можна: command -v fpc
# пропустив би й ці пакети — саме ця помилка зламала Lazarus-прогін.
unconditional=0
while IFS= read -r line; do
  case "$line" in
    *"command -v fpc"*) continue ;;
  esac
  pkgs=$(printf '%s' "$line" | sed 's/.*apt-get install//' | tr ' ' '\n' | grep -v '^-' | grep -vE '^[0-9]+s$' | grep -vE '^(apt-get|install|sudo|timeout)?$' || true)
  extra=$(printf '%s\n' "$pkgs" | grep -vE '^(fp-compiler|git)$' || true)
  [ -z "$extra" ] && unconditional=$((unconditional+1))
done < <(grep -h "apt-get install" .github/workflows/*.yml)
recommends=$(grep -h "apt-get install" .github/workflows/*.yml | grep -vc "no-install-recommends" || true)

echo "CI-APT workflows=$total захищених=$guarded безумовних=$unconditional з-recommends=$recommends"
if [ "$unconditional" -ne 0 ]; then echo "CI-APT-FAIL: є безумовні apt-get install"; fail=1; fi
if [ "$recommends" -ne 0 ]; then echo "CI-APT-FAIL: є встановлення без --no-install-recommends"; fail=1; fi
if [ "$fail" -ne 0 ]; then exit 1; fi
echo "CI-APT-PASS"
