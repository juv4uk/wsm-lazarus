#!/usr/bin/env bash
# G6.158 — перевіряємо арифметику RAPL та справжню FPC→ELF вертикаль.
# У CI лічильники синтетичні. Результат НЕ є джоулями з CPU.
set -Eeuo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok() { CHECKS=$((CHECKS+1)); printf 'FIB-ENERGY-TEST-OK %s\n' "$1"; }
bad() { printf 'FIB-ENERGY-TEST-ЗБІЙ %s\n' "$1" >&2; exit 1; }
reject() {
  local caption="$1" output code
  shift
  if output=$("$@" 2>&1); then
    bad "$caption: прийнято невалідний ввід"
  else
    code=$?
  fi
  [[ "$code" -eq 2 && "$output" == *'FIB-ENERGY-ВІДМОВА'* &&
     "$output" != *'сер.='* && "$output" != *'FIB-ENERGY-PASS'* ]] ||
    bad "$caption: немає явної відмови без числового звіту ($code): $output"
  ok "$caption — відмова без псевдоенергії"
}

# Source лише визначає host-функцію: не збирає Free Pascal автоматично.
source "$ROOT/scripts/run-fib-energy.sh"
[[ "$(rapl_delta 990000 100000 1000000 1000000)" == 110000 ]] ||
  bad 'один wrap повинен використовувати max_energy_range_uj'
ok 'арифметика одного справжнього modulo wrap'
[[ "$(rapl_delta 150 200 1000000 1000000)" == 50 ]] ||
  bad 'звичайний монотонний лічильник'
ok 'монотонний приріст'
reject 'недопустиме значення energy_uj' \
  bash -c 'source "$1"; rapl_delta 1000000 1 1000000 1000000' \
  _ "$ROOT/scripts/run-fib-energy.sh"
reject 'нечислова межа' \
  bash -c 'source "$1"; rapl_delta 0 1 зіпсовано 1000000' \
  _ "$ROOT/scripts/run-fib-energy.sh"
reject 'ризик кількох обертів' \
  bash -c 'source "$1"; rapl_delta 900000 100000 1000000 3000000' \
  _ "$ROOT/scripts/run-fib-energy.sh"

mkdir -p "$TMP/empty" "$TMP/rapl/intel-rapl:0"
printf 'package-0\n' > "$TMP/rapl/intel-rapl:0/name"
printf '2000000\n' > "$TMP/rapl/intel-rapl:0/max_energy_range_uj"
printf '1000000\n' > "$TMP/rapl/intel-rapl:0/energy_uj"

reject 'відсутній package' env FIB_RAPL_ROOT="$TMP/empty" \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT"

mv "$TMP/rapl/intel-rapl:0/max_energy_range_uj" "$TMP/max.saved"
reject 'немає max_energy_range_uj' env FIB_RAPL_ROOT="$TMP/rapl" \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT"
mv "$TMP/max.saved" "$TMP/rapl/intel-rapl:0/max_energy_range_uj"

printf 'зіпсовано\n' > "$TMP/rapl/intel-rapl:0/energy_uj"
reject 'нечисловий energy_uj' env FIB_RAPL_ROOT="$TMP/rapl" \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT"

printf '2000000\n' > "$TMP/rapl/intel-rapl:0/energy_uj"
reject 'energy_uj за межею' env FIB_RAPL_ROOT="$TMP/rapl" \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT"

printf '1000000\n' > "$TMP/rapl/intel-rapl:0/energy_uj"
printf 'package-інша\n' > "$TMP/rapl/intel-rapl:0/name"
reject 'назва не збігається з package' env FIB_RAPL_ROOT="$TMP/rapl" \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT"
printf 'package-0\n' > "$TMP/rapl/intel-rapl:0/name"

mkdir -p "$TMP/rapl/intel-rapl:1"
printf 'package-1\n' > "$TMP/rapl/intel-rapl:1/name"
reject 'кілька package — неоднозначний вимір' env FIB_RAPL_ROOT="$TMP/rapl" \
  bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT"
rmdir "$TMP/rapl/intel-rapl:1"

# Цей шлях у CI обов'язково збирає САМЕ реальний sensfiblower через FPC,
# запускає створений ELF та перевіряє correctness перед і під час виміру.
if output=$(FIB_RAPL_ROOT="$TMP/rapl" FIB_REPEATS=1 FIB_N=10 \
    timeout 180s bash "$ROOT/scripts/run-fib-energy.sh" "$ROOT" 2>&1); then
  :
else
  bad "реальна FPC→ELF вертикаль: $output"
fi
[[ "$output" == *'FIB-ENERGY-PASS'* ]] ||
  bad 'реальний ELF не завершив протокол'
ok 'реальна FPC→ELF вертикаль'
[[ "$output" == *'СИМУЛЬОВАНИЙ'* &&
   "$output" == *'НЕ вимір джоулів'* ]] ||
  bad 'фальшивий лічильник не позначений'
ok 'синтетика не видається за реальні джоулі'
[[ "$output" == *'max_energy_range_uj=2000000'* &&
   "$output" == *'мкДж за прогін (package + фон)'* ]] ||
  bad 'не прозорий домен/одиниці RAPL'
ok 'метадані виміру називають фізичний модуль та домен'
printf 'FIB-ENERGY-TEST-PASS checks=%s energy=НЕ-ВИМІРЯНО\n' "$CHECKS"
