#!/usr/bin/env bash
# G6.141 — близнюки навантаження `loop`: збірка і ЗВІРКА КОДІВ ВИХОДУ.
#
# Тіло в усіх близнюках ОДНЕ: N разів додати сталу K, код виходу = сума & 255.
# Це друге навантаження після `fib` у списку pinned SENS
# (fib, loop, ackermann, closures, evenodd).
#
# SENS-бік тут НЕ переписано: нативний цикл дає чинний механізм
# `wsm.elfd12loop` (D12-стала з pinned .sens), який має власний тест
# `scripts/test-d12loop.sh` (35 перевірок). Цей скрипт звіряє ТРИ
# програмні близнюки з тим самим оракулом — щоб тіло було доведено
# однаковим перш ніж міряти час чи енергію.
#
# Без --measure скрипт нічого не міряє.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MEASURE=0
REPEATS="${LOOP_REPEATS:-5}"
NS="${LOOP_NS:-1000 1000000 20000000}"
K="${LOOP_K:-1}"

shift || true
for arg in "$@"; do
  [ "$arg" = "--measure" ] && MEASURE=1
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0

say() { printf 'LOOP-TWINS %s\n' "$*"; }
bad() { printf 'LOOP-TWINS-ЗБІЙ %s\n' "$*"; FAIL=1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Незалежний оракул: не мій емітер і не жоден близнюк.
# Сума N додавань K із маскуванням на кожному кроці тотожна (N*K) mod 256,
# тому оракул — арифметика, а не цикл: він не залежить від швидкості хоста
# і не може «зійтися» з близнюком через спільну помилку лічби.
oracle() {
  local n="$1" k="$2"
  echo $(( (n % 256) * (k % 256) % 256 ))
}

have fpc || { echo "LOOP-TWINS-БЛОК: немає fpc" >&2; exit 127; }

fpc -B -O2 -FU"$WORK/u" -FE"$WORK/b" -oloop-pas \
  "$ROOT/benchmarks/cross-language/loop/loop.pas" > "$WORK/build-pas.log" 2>&1 \
  || { bad "збірка FPC-близнюка"; cat "$WORK/build-pas.log"; exit 1; }
say "FPC: зібрано"

if have gcc; then say "C: gcc є"; else say "C: gcc відсутній — лише CI"; fi

if have rustc; then
  rustc -O -o "$WORK/loop-rs" \
    "$ROOT/benchmarks/cross-language/loop/loop.rs" 2> "$WORK/build-rs.log" \
    || { bad "збірка Rust-близнюка"; cat "$WORK/build-rs.log"; }
  say "Rust: зібрано"
else
  say "Rust: rustc відсутній — лише CI"
fi

for N in $NS; do
  WANT="$(oracle "$N" "$K")"
  set +e
  "$WORK/b/loop-pas" "$N" "$K"
  GOT=$?
  set -e
  [ "$GOT" = "$WANT" ] || bad "FPC loop(N=$N)=$GOT, оракул $WANT"

  if have gcc; then
    gcc -O2 -DLOOP_N="$N" -DLOOP_K="$K" -o "$WORK/loop-c" \
      "$ROOT/benchmarks/cross-language/loop/loop.c" 2> "$WORK/build-c.log" \
      || { bad "збірка C-близнюка для N=$N"; cat "$WORK/build-c.log"; }
    if [ -x "$WORK/loop-c" ]; then
      set +e; "$WORK/loop-c"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "C loop(N=$N)=$GOT, оракул $WANT"
    fi
  fi
  if [ -x "$WORK/loop-rs" ]; then
    set +e; LOOP_N="$N" LOOP_K="$K" "$WORK/loop-rs"; GOT=$?; set -e
    [ "$GOT" = "$WANT" ] || bad "Rust loop(N=$N)=$GOT, оракул $WANT"
  fi
  say "N=$N K=$K оракул=$WANT звірено"
done

if [ "$MEASURE" -eq 1 ]; then
  say "походження: SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  say "походження: CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
  for N in $NS; do
    best=999999
    for ((r=0; r<REPEATS; r++)); do
      t0=$(date +%s%N); "$WORK/b/loop-pas" "$N" "$K"; t1=$(date +%s%N)
      ms=$(( (t1 - t0) / 1000000 ))
      [ "$ms" -lt "$best" ] && best=$ms
    done
    say "N=$N loop-pas мін.=$best мс"
  done
else
  say "вимірювання не запускалося (додайте --measure)"
fi

if [ "$FAIL" -ne 0 ]; then echo "LOOP-TWINS-FAIL"; exit 1; fi
echo "LOOP-TWINS-PASS"
