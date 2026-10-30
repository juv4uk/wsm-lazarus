#!/usr/bin/env bash
# G6.156 — гейт проти безумовного встановлення FPC у кожному прогоні.
# Вимога власника: не витрачати енергію на важкі/повторні встановлення.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
total=$(ls .github/workflows/*.yml | wc -l)
guarded=$(grep -l "command -v fpc" .github/workflows/*.yml | wc -l)
unconditional=$(grep -l "apt-get install" .github/workflows/*.yml | xargs grep -L "command -v fpc" 2>/dev/null | wc -l)
recommends=$(grep -h "apt-get install" .github/workflows/*.yml | grep -vc "no-install-recommends" || true)

echo "CI-APT workflows=$total захищених=$guarded безумовних=$unconditional з-recommends=$recommends"
if [ "$unconditional" -ne 0 ]; then echo "CI-APT-FAIL: є безумовні apt-get install"; fail=1; fi
if [ "$recommends" -ne 0 ]; then echo "CI-APT-FAIL: є встановлення без --no-install-recommends"; fail=1; fi
if [ "$fail" -ne 0 ]; then exit 1; fi
echo "CI-APT-PASS"
