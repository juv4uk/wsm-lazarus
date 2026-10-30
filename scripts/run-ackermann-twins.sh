#!/usr/bin/env bash
# G6.145 — близнюки навантаження `ackermann`: збірка і ЗВІРКА КОДІВ ВИХОДУ.
#
# Тіло в усіх близнюках ОДНЕ:
#   ack(m,n) = n+1 | ack(m-1,1) | ack(m-1, ack(m,n-1)), код виходу = & 255.
# SENS-бік — чинне зниження `wsm.lowerd24` (LOWER24-PASS перевіряє його
# на тих самих парах m,n). Цей скрипт звіряє ТРИ програмні близнюки з
# незалежним оракулом, щоб тіло було доведено однаковим.
#
# Без --measure скрипт нічого не міряє.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MEASURE=0
REPEATS="${ACK_REPEATS:-5}"
PAIRS="${ACK_PAIRS:-0,3 1,2 2,2 3,3 2,3}"

shift || true
for arg in "$@"; do
  [ "$arg" = "--measure" ] && MEASURE=1
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0

say() { printf 'ACK-TWINS %s\n' "$*"; }
bad() { printf 'ACK-TWINS-ЗБІЙ %s\n' "$*"; FAIL=1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Незалежний оракул: та сама математика, але іншою мовою (awk), щоб
# помилка в одній реалізації не «зійшлася» сама з собою.
# Оракул — Python із піднятою межею рекурсії. AWK тут не годиться: його
# стек (1024) падає вже на ack(3,8), і тоді «звірено» стає неправдою.
oracle() {
  python3 - "$1" "$2" <<'PYORACLE'
import sys
sys.setrecursionlimit(200000)
m, n = int(sys.argv[1]), int(sys.argv[2])
def ack(m, n):
    if m == 0:
        return n + 1
    if n == 0:
        return ack(m - 1, 1)
    return ack(m - 1, ack(m, n - 1))
print(ack(m, n) % 256)
PYORACLE
}

have fpc || { echo "ACK-TWINS-БЛОК: немає fpc" >&2; exit 127; }
fpc -B -O2 -FU"$WORK/u" -FE"$WORK/b" -oack-pas \
  "$ROOT/benchmarks/cross-language/ackermann/ackermann.pas" > "$WORK/build-pas.log" 2>&1 \
  || { bad "збірка FPC-близнюка"; cat "$WORK/build-pas.log"; exit 1; }
say "FPC: зібрано"
if have gcc; then say "C: gcc є"; else say "C: gcc відсутній — лише CI"; fi
if have rustc; then say "Rust: rustc є"; else say "Rust: rustc відсутній — лише CI"; fi

for pair in $PAIRS; do
  M="${pair%%,*}"; N="${pair##*,}"
  WANT="$(oracle "$M" "$N")"

  set +e; "$WORK/b/ack-pas" "$M" "$N"; GOT=$?; set -e
  [ "$GOT" = "$WANT" ] || bad "FPC ack($M,$N)=$GOT, оракул $WANT"

  if have gcc; then
    gcc -O2 -o "$WORK/ack-c" "$ROOT/benchmarks/cross-language/ackermann/ackermann.c" \
      2> "$WORK/build-c.log" || { bad "збірка C-близнюка"; cat "$WORK/build-c.log"; }
    if [ -x "$WORK/ack-c" ]; then
      set +e; "$WORK/ack-c" "$M" "$N"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "C ack($M,$N)=$GOT, оракул $WANT"
    fi
  fi
  if have rustc; then
    rustc -O -o "$WORK/ack-rs" "$ROOT/benchmarks/cross-language/ackermann/ackermann.rs" \
      2> "$WORK/build-rs.log" || { bad "збірка Rust-близнюка"; cat "$WORK/build-rs.log"; }
    if [ -x "$WORK/ack-rs" ]; then
      set +e; "$WORK/ack-rs" "$M" "$N"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "Rust ack($M,$N)=$GOT, оракул $WANT"
    fi
  fi
  say "ack($M,$N) оракул=$WANT звірено"
done

if [ "$MEASURE" -eq 1 ]; then
  say "походження: SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  say "походження: CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
  for pair in $PAIRS; do
    M="${pair%%,*}"; N="${pair##*,}"
    best=999999
    for ((r=0; r<REPEATS; r++)); do
      t0=$(date +%s%N); set +e; "$WORK/b/ack-pas" "$M" "$N"; set -e; t1=$(date +%s%N)
      ms=$(( (t1 - t0) / 1000000 ))
      [ "$ms" -lt "$best" ] && best=$ms
    done
    say "ack($M,$N) ack-pas мін.=$best мс"
  done
else
  say "вимірювання не запускалося (додайте --measure)"
fi

if [ "$FAIL" -ne 0 ]; then echo "ACK-TWINS-FAIL"; exit 1; fi
echo "ACK-TWINS-PASS"
