#!/usr/bin/env bash
# G6.158 — протокол енергії для фізично скомпільованого SENS fib.
# package-level RAPL не дорівнює енергії самого процесу; це енергія CPU package
# із системним фоном. SIMULATED є тільки тестом протоколу, не виміром.
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RAPL="${FIB_RAPL_ROOT:-/sys/class/powercap}"
REPEATS="${FIB_REPEATS:-5}"
N="${FIB_N:-32}"
SIMULATED=0
[[ -z "${FIB_RAPL_ROOT:-}" ]] || SIMULATED=1

fail() { printf 'FIB-ENERGY-ВІДМОВА %s\n' "$*" >&2; exit 2; }

# Host input (energy_uj/max_energy_range_uj) — тільки ASCII unsigned decimal.
# Фізичне слово SENS тут не читається: це окремий Linux host-протокол.
# 1) Чому не допустимо без перевірки застосувати Bash-арифметику до sysfs?
# 2) Чому обмеження на цифри захищає від переповнення host integer?
read_unsigned() {
  local value
  [[ -r "$1" ]] || fail "немає доступного RAPL файла: $1"
  IFS= read -r value < "$1" || [[ -n "$value" ]] ||
    fail "порожній RAPL лічильник: $1"
  [[ "$value" =~ ^[0-9]+$ && ${#value} -le 13 ]] ||
    fail "лічильник не є допустимим цілим: $1"
  printf '%s\n' "$((10#$value))"
}

# Модуль ОБОВ'ЯЗКОВО береться з того самого package, що energy_uj.
# elapsed_ns borrowed host-таймер; максимум 500 W — консервативна межа
# прийнятності одного читання, а не заявлена потужність процесора SENS.
# Результат — signed host integer мкДж, ніколи не синтаксис числа D12+.
# 1) Чому модуль не можна зашити константою?
# 2) Чому два оберти не відновлюються з двох показів?
# 3) Чому synthetic fixture не доводить реальну енергію?
rapl_delta() {
  local before="$1" after="$2" maximum="$3" elapsed_ns="$4"
  [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ &&
     "$maximum" =~ ^[0-9]+$ && "$elapsed_ns" =~ ^[0-9]+$ ]] ||
    fail 'нечислове значення RAPL delta'
  ((maximum>1 && maximum<=1000000000000 &&
    before<maximum && after<maximum && elapsed_ns>0)) ||
    fail 'RAPL delta поза фізичною межею'
  if ((SIMULATED == 0 && elapsed_ns * 500 >= maximum * 1000)); then
    fail 'RAPL може мати кілька обертів за один запуск; енергію не виміряно'
  fi
  printf '%s\n' "$(((after-before+maximum)%maximum))"
}

# Скануємо рівно ОДИН package-N; core/uncore-діти не підсумовуємо.
# Package name мусить збігатися з адресою, щоб не обрати випадкову зону.
discover_package() {
  local zone index label count=0
  [[ -d "$RAPL" ]] || fail "немає каталогу RAPL: $RAPL"
  shopt -s nullglob
  for zone in "$RAPL"/intel-rapl:*; do
    [[ -d "$zone" ]] || continue
    index="${zone##*:}"
    [[ "$index" =~ ^[0-9]+$ ]] || continue
    [[ -r "$zone/name" ]] || fail "немає назви RAPL package: $zone"
    IFS= read -r label < "$zone/name" ||
      fail "нечитабельна назва RAPL package: $zone"
    [[ "$label" == "package-$index" ]] ||
      fail "невідповідна назва RAPL package: $zone"
    count=$((count+1))
    PACKAGE="$zone"
  done
  shopt -u nullglob
  ((count==1)) || fail "потрібен рівно один RAPL package, знайдено: $count"
  MAX=$(read_unsigned "$PACKAGE/max_energy_range_uj")
  ((MAX>1 && MAX<=1000000000000)) || fail 'некоректна межа RAPL package'
  read_uj >/dev/null
}

read_uj() {
  local value
  value=$(read_unsigned "$PACKAGE/energy_uj")
  ((value<MAX)) || fail 'energy_uj поза max_energy_range_uj'
  printf '%s\n' "$value"
}

main() {
  [[ "$REPEATS" =~ ^[1-9][0-9]*$ && ${#REPEATS} -le 2 ]] ||
    fail 'кількість повторів має бути 1..30'
  ((10#$REPEATS<=30)) || fail 'кількість повторів має бути 1..30'
  [[ "$N" =~ ^(0|[1-9][0-9]*)$ && ${#N} -le 2 ]] ||
    fail 'fib N має бути 0..35'
  ((10#$N<=35)) || fail 'fib N має бути 0..35'
  discover_package
  for tool in fpc timeout git date mktemp; do
    command -v "$tool" >/dev/null || fail "немає $tool"
  done
  local work want got before after elapsed_ns start end delta total=0 r
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/u" "$work/b"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci \
    -Fu"$ROOT/src" -FU"$work/u" -FE"$work/b" \
    -osensfiblower "$ROOT/src/sensfiblower.lpr" \
    >"$work/build.log" 2>&1 || fail 'не вдалося зібрати sensfiblower'
  timeout 90s "$work/b/sensfiblower" "$ROOT" "$N" "$work/fib-sens" \
    >"$work/lower.out" 2>"$work/lower.err" ||
    fail 'не вдалося понизити реальне фізичне тіло SENS'
  [[ -f "$work/fib-sens" ]] || fail 'компілятор не створив ELF'
  chmod +x "$work/fib-sens"

  # Незалежна арифметика host є тестовим oracle, НЕ новим законом SENS.
  local a=0 b=1 t i
  for ((i=0;i<10#$N;i++)); do t=$((a+b)); a=$b; b=$t; done
  want=$((a & 255))
  if "$work/fib-sens" >"$work/execution.out" 2>"$work/execution.err"; then
    got=0
  else
    got=$?
  fi
  [[ "$got" -eq "$want" && ! -s "$work/execution.out" &&
     ! -s "$work/execution.err" ]] ||
    fail "неправильний fib($N): ELF exit=$got, oracle=$want"

  for ((r=0;r<10#$REPEATS;r++)); do
    before=$(read_uj)
    start=$(date +%s%N)
    if "$work/fib-sens" >"$work/execution.out" 2>"$work/execution.err"; then
      got=0
    else
      got=$?
    fi
    end=$(date +%s%N)
    after=$(read_uj)
    [[ "$got" -eq "$want" && ! -s "$work/execution.out" &&
       ! -s "$work/execution.err" ]] ||
      fail "помилковий виміряний ELF запуск #$((r+1)): exit=$got"
    elapsed_ns=$((end-start))
    delta=$(rapl_delta "$before" "$after" "$MAX" "$elapsed_ns")
    total=$((total+delta))
  done

  # Жодного часткового числового звіту до ВСІХ успішних вимірів.
  printf 'FIB-ENERGY n=%s repeats=%s\n' "$N" "$REPEATS"
  printf 'FIB-ENERGY домен=%s max_energy_range_uj=%s\n' "$PACKAGE" "$MAX"
  printf 'FIB-ENERGY SHA=%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  if ((SIMULATED)); then
    printf 'FIB-ENERGY СИМУЛЬОВАНИЙ: це тест лічильника, НЕ вимір джоулів\n'
  fi
  printf 'FIB-ENERGY fib-sens сер.=%s мкДж за прогін (package + фон)\n' \
    "$((total / (10#$REPEATS)))"
  printf 'FIB-ENERGY-PASS\n'
}

# Джерело можна source лише для ізольованої перевірки rapl_delta,
# але звичайне виконання завжди запускає реальну FPC/ELF вертикаль.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
