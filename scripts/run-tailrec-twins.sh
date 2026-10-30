#!/usr/bin/env bash
# G6.156 — близнюки хвостової рекурсії: SENS-ELF (зниження) і FPC/C.
#
# Тіло ОДНЕ: count_down(n, acc) = acc, якщо n<1; інакше count_down(n-1, acc+1).
# Самовиклик — хвіст, тому глибина не обмежена стеком (G6.154/G6.155).
# Оракул — не переписане тіло, а властивість: count_down(n,0) = n.
#
# Без --measure нічого не міряє.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MEASURE=0; REPEATS="${TR_REPEATS:-5}"
NS="${TR_NS:-0 1 2 7 255 256 100000 1000000}"
shift || true
for a in "$@"; do [ "$a" = "--measure" ] && MEASURE=1; done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0
say() { printf 'TR-TWINS %s\n' "$*"; }
bad() { printf 'TR-TWINS-ЗБІЙ %s\n' "$*"; FAIL=1; }
have() { command -v "$1" >/dev/null 2>&1; }
oracle() { printf '%s\n' "$(( $1 % 256 ))"; }

have fpc || { echo "TR-TWINS-БЛОК: немає fpc" >&2; exit 127; }
fpc -B -O2 -FU"$WORK/u" -FE"$WORK/b" -otr-pas \
  "$ROOT/benchmarks/cross-language/tailrec/tailrec.pas" >"$WORK/bp.log" 2>&1 \
  || { bad "збірка FPC"; cat "$WORK/bp.log"; exit 1; }
say "FPC: зібрано"

for N in $NS; do
  WANT="$(oracle "$N")"
  set +e; "$WORK/b/tr-pas" "$N"; GOT=$?; set -e
  [ "$GOT" = "$WANT" ] || bad "FPC count_down($N)=$GOT, очікували $WANT"
  if have gcc; then
    gcc -O2 -o "$WORK/tr-c" "$ROOT/benchmarks/cross-language/tailrec/tailrec.c" 2>"$WORK/bc.log" \
      || bad "збірка C"
    if [ -x "$WORK/tr-c" ]; then
      set +e; "$WORK/tr-c" "$N"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "C count_down($N)=$GOT, очікували $WANT"
    fi
  fi
  say "count_down($N) = $WANT звірено"
done
have gcc || say "C: gcc відсутній — лише CI"
have rustc || say "Rust: rustc відсутній — лише CI (важкий тулчейн, не на кожен пуш)"

if [ "$MEASURE" -eq 1 ]; then
  say "походження: SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  say "походження: CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
  for N in $NS; do
    best=999999999
    for ((r=0; r<REPEATS; r++)); do
      t0=$(date +%s%N); set +e; "$WORK/b/tr-pas" "$N"; set -e; t1=$(date +%s%N)
      ms=$(( (t1-t0)/1000000 )); [ "$ms" -lt "$best" ] && best=$ms
    done
    say "count_down($N) tr-pas мін.=$best мс"
  done
else
  say "вимірювання не запускалося (додайте --measure)"
fi
[ "$FAIL" -ne 0 ] && { echo "TR-TWINS-FAIL"; exit 1; }
echo "TR-TWINS-PASS"
