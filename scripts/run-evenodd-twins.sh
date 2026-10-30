#!/usr/bin/env bash
# G6.150 — близнюки навантаження `evenodd`: збірка і ЗВІРКА КОДІВ ВИХОДУ.
#
# Тіло в усіх близнюках ОДНЕ (взаємна рекурсія):
#   even(n) = 1 якщо n < 1, інакше odd(n-1)
#   odd(n)  = 0 якщо n < 1, інакше even(n-1)
# Код виходу = even(n) & 255, тобто 1 для парних і 0 для непарних.
#
# SENS-бік — чинне зниження LowerPairELF (G6.149), яке перевіряє
# LOWER24-PASS на тих самих n. Цей скрипт звіряє ТРИ програмні близнюки
# з незалежним оракулом.
#
# Без --measure скрипт нічого не міряє.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MEASURE=0
REPEATS="${EO_REPEATS:-5}"
NS="${EO_NS:-0 1 2 5 8 999 100000}"

shift || true
for arg in "$@"; do
  [ "$arg" = "--measure" ] && MEASURE=1
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0

say() { printf 'EO-TWINS %s\n' "$*"; }
bad() { printf 'EO-TWINS-ЗБІЙ %s\n' "$*"; FAIL=1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Оракул — арифметика, не рекурсія: парність визначається остачею.
# Це не «те саме тіло іншою мовою», а незалежна властивість числа.
oracle() { python3 -c "import sys; print(1 if int(sys.argv[1]) % 2 == 0 else 0)" "$1"; }

have fpc || { echo "EO-TWINS-БЛОК: немає fpc" >&2; exit 127; }
fpc -B -O2 -FU"$WORK/u" -FE"$WORK/b" -oeo-pas \
  "$ROOT/benchmarks/cross-language/evenodd/evenodd.pas" > "$WORK/build-pas.log" 2>&1 \
  || { bad "збірка FPC-близнюка"; cat "$WORK/build-pas.log"; exit 1; }
say "FPC: зібрано"
if have gcc; then say "C: gcc є"; else say "C: gcc відсутній — лише CI"; fi
if have rustc; then say "Rust: rustc є"; else say "Rust: rustc відсутній — лише CI"; fi

for N in $NS; do
  WANT="$(oracle "$N")"
  set +e; "$WORK/b/eo-pas" "$N"; GOT=$?; set -e
  [ "$GOT" = "$WANT" ] || bad "FPC even($N)=$GOT, оракул $WANT"

  if have gcc; then
    gcc -O2 -o "$WORK/eo-c" "$ROOT/benchmarks/cross-language/evenodd/evenodd.c" \
      2> "$WORK/build-c.log" || { bad "збірка C-близнюка"; cat "$WORK/build-c.log"; }
    if [ -x "$WORK/eo-c" ]; then
      set +e; "$WORK/eo-c" "$N"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "C even($N)=$GOT, оракул $WANT"
    fi
  fi
  if have rustc; then
    rustc -O -o "$WORK/eo-rs" "$ROOT/benchmarks/cross-language/evenodd/evenodd.rs" \
      2> "$WORK/build-rs.log" || { bad "збірка Rust-близнюка"; cat "$WORK/build-rs.log"; }
    if [ -x "$WORK/eo-rs" ]; then
      set +e; "$WORK/eo-rs" "$N"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "Rust even($N)=$GOT, оракул $WANT"
    fi
  fi
  say "even($N) оракул=$WANT звірено"
done

if [ "$MEASURE" -eq 1 ]; then
  say "походження: SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  say "походження: CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
  for N in $NS; do
    best=999999
    for ((r=0; r<REPEATS; r++)); do
      t0=$(date +%s%N); set +e; "$WORK/b/eo-pas" "$N"; set -e; t1=$(date +%s%N)
      ms=$(( (t1 - t0) / 1000000 ))
      [ "$ms" -lt "$best" ] && best=$ms
    done
    say "even($N) eo-pas мін.=$best мс"
  done
else
  say "вимірювання не запускалося (додайте --measure)"
fi

if [ "$FAIL" -ne 0 ]; then echo "EO-TWINS-FAIL"; exit 1; fi
echo "EO-TWINS-PASS"
