#!/usr/bin/env bash
# G6.99 — ПРОТОКОЛ ЕНЕРГІЇ для навантаження `fib`.
#
# Час процесу НЕ є енергією. Енергія береться з апаратних лічильників
# RAPL (`/sys/class/powercap/intel-rapl:*/energy_uj`). Якщо їх немає —
# скрипт ЧЕСНО ВІДМОВЛЯЄТЬСЯ і нічого не друкує, а не підміняє енергію
# часом або оцінкою.
#
# FIB_RAPL_ROOT — лише для ПЕРЕВІРКИ САМОГО ПРОТОКОЛУ на машинах без
# RAPL: підставляє теку з файлами energy_uj. Числа з такого прогону
# позначені як СИМУЛЬОВАНІ і не є виміром енергії.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
RAPL="${FIB_RAPL_ROOT:-/sys/class/powercap}"
REPEATS="${FIB_REPEATS:-5}"
N="${FIB_N:-32}"
SIMULATED=0
[ -n "${FIB_RAPL_ROOT:-}" ] && SIMULATED=1

fail() { printf 'FIB-ENERGY-ВІДМОВА %s\n' "$*"; exit 2; }

# Домен шукаємо явно: intel-rapl:0 — пакет, intel-rapl:0:0 — ядра.
DOMAIN=""
for candidate in "$RAPL"/intel-rapl:*/energy_uj; do
  [ -r "$candidate" ] || continue
  DOMAIN="$candidate"
  break
done
[ -n "$DOMAIN" ] || fail "немає RAPL-лічильників у $RAPL — енергію виміряти неможливо"

read_uj() { cat "$DOMAIN"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"

# 1. Спершу — ПРАВИЛЬНІСТЬ. Без неї енергія не має сенсу.
fpc -B -Mobjfpc -Cr -Co -Ci -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -osensfiblower "$ROOT/src/sensfiblower.lpr" > "$WORK/build.log" 2>&1 \
  || fail "збірка sensfiblower"
"$WORK/b/sensfiblower" "$ROOT" "$N" "$WORK/fib-sens" || fail "зниження тіла SENS"
chmod +x "$WORK/fib-sens"

oracle() {
  local n="$1" a=0 b=1 t i
  for ((i=0; i<n; i++)); do t=$((a+b)); a=$b; b=$t; done
  echo $((a & 255))
}
WANT="$(oracle "$N")"
set +e; "$WORK/fib-sens"; GOT=$?; set -e
[ "$GOT" = "$WANT" ] || fail "SENS-lowered fib($N)=$GOT, оракул $WANT"

printf 'FIB-ENERGY n=%s repeats=%s\n' "$N" "$REPEATS"
printf 'FIB-ENERGY домен=%s\n' "$DOMAIN"
printf 'FIB-ENERGY SHA=%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
printf 'FIB-ENERGY CPU=%s\n' "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
if [ "$SIMULATED" -eq 1 ]; then
  printf 'FIB-ENERGY УВАГА: лічильник СИМУЛЬОВАНИЙ (%s) — це перевірка протоколу, НЕ вимір енергії\n' "$RAPL"
fi

for twin in fib-sens; do
  total=0
  for ((r=0; r<REPEATS; r++)); do
    before="$(read_uj)"
    set +e; "$WORK/$twin"; set -e
    after="$(read_uj)"
    delta=$((after - before))
    [ "$delta" -ge 0 ] || delta=$((delta + 1000000000))
    total=$((total + delta))
  done
  printf 'FIB-ENERGY %s сер.=%s мкДж за прогін\n' "$twin" "$((total / REPEATS))"
done

echo "FIB-ENERGY-PASS"
