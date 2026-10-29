#!/usr/bin/env bash
# G6.99 — перевірка ПРОТОКОЛУ енергії (не вимір енергії).
# 1. Без RAPL скрипт мусить ВІДМОВИТИСЬ (код 2), а не вигадати число.
# 2. З підставленим лічильником мусить пройти шлях і позначити
#    симуляцію — тобто сам протокол працює.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAIL=0

ok() { printf 'FIB-ENERGY-TEST-OK   %s\n' "$1"; }
bad() { printf 'FIB-ENERGY-TEST-ЗБІЙ %s\n' "$1"; FAIL=1; }

# 1. Відмова без лічильників
mkdir -p "$WORK/empty"
set +e
FIB_RAPL_ROOT="" bash -c "unset FIB_RAPL_ROOT; RAPL_DIR='$WORK/empty'" >/dev/null 2>&1
out=$(bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT" 2>&1)
code=$?
set -e
if [ "$code" -eq 2 ] && printf '%s' "$out" | grep -q 'ВІДМОВА'; then
  ok "без RAPL — явна відмова (код 2)"
else
  bad "без RAPL скрипт не відмовився (код $code)"
fi

# 2. Підставлений лічильник — протокол проходить шлях
mkdir -p "$WORK/rapl/intel-rapl:0"
printf '1000000\n' > "$WORK/rapl/intel-rapl:0/energy_uj"
set +e
out2=$(FIB_RAPL_ROOT="$WORK/rapl" FIB_REPEATS=1 FIB_N=10 \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT" 2>&1)
code2=$?
set -e
if [ "$code2" -eq 0 ] && printf '%s' "$out2" | grep -q 'FIB-ENERGY-PASS'; then
  ok "з підставленим лічильником протокол проходить"
else
  bad "протокол не пройшов із підставленим лічильником (код $code2)"
  printf '%s\n' "$out2" | tail -5
fi
if printf '%s' "$out2" | grep -q 'СИМУЛЬОВАНИЙ'; then
  ok "симуляція явно позначена в звіті"
else
  bad "симуляція НЕ позначена — це було б підміною виміру"
fi
if printf '%s' "$out2" | grep -q 'мкДж'; then
  ok "одиниця енергії названа (мкДж)"
else
  bad "одиниця енергії не названа"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "FIB-ENERGY-TEST-FAIL"
  exit 1
fi
echo "FIB-ENERGY-TEST-PASS checks=4"
echo "FIB-ENERGY-TEST-LIMIT=protocol-only-real-energy-needs-RAPL-hardware"
