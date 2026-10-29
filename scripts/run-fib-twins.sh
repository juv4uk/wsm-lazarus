#!/usr/bin/env bash
# G6.94 — близнюки навантаження `fib`: збірка, ЗВІРКА КОДІВ ВИХОДУ
# з незалежним оракулом, і — лише за --measure — вимірювання часу.
#
# Без --measure скрипт нічого не міряє: він доводить, що всі близнюки
# рахують те саме. Числа публікуються лише разом із походженням.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MEASURE=0
REPEATS="${FIB_REPEATS:-5}"
NS="${FIB_NS:-10 20 25 30 35}"

shift || true
for arg in "$@"; do
  [ "$arg" = "--measure" ] && MEASURE=1
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0

oracle() {
  local n="$1" a=0 b=1 t i
  for ((i=0; i<n; i++)); do t=$((a+b)); a=$b; b=$t; done
  echo $((a & 255))
}

have() { command -v "$1" >/dev/null 2>&1; }

say() { printf 'FIB-TWINS %s\n' "$*"; }
bad() { printf 'FIB-TWINS-ЗБІЙ %s\n' "$*"; FAIL=1; }

# Нативний SENS-шлях: ELF із точного D24 .sens.
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -otest-elffib "$ROOT/scripts/test-elffib.pas" > "$WORK/build-elffib.log" 2>&1 \
  || { bad "збірка емітера SENS-ELF"; exit 1; }
"$WORK/b/test-elffib" > "$WORK/elffib.log" 2>&1 \
  || { bad "самотест SENS-ELF"; cat "$WORK/elffib.log"; exit 1; }
say "SENS-ELF: самотест PASS"

# Тіло SENS, знижене в машинний код (не host-код навантаження).
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -osensfiblower "$ROOT/src/sensfiblower.lpr" > "$WORK/build-lower.log" 2>&1 \
  || { bad "збірка sensfiblower"; cat "$WORK/build-lower.log"; exit 1; }
say "SENS-lowered: емітер зібрано"

for N in $NS; do
  WANT="$(oracle "$N")"

  # C
  if have gcc; then
    gcc -O2 -DN="$N" -o "$WORK/fib-c" "$ROOT/benchmarks/cross-language/fib/fib.c"
    set +e; "$WORK/fib-c"; GOT=$?; set -e
    [ "$GOT" = "$WANT" ] || bad "C fib($N)=$GOT, оракул $WANT"
  fi

  # Rust: include! шукає файл ПОРУЧ із джерелом, тому копіюємо fib.rs
  # у робочу теку й генеруємо fib_n.rs там само.
  if have rustc; then
    cp "$ROOT/benchmarks/cross-language/fib/fib.rs" "$WORK/fib.rs"
    printf 'const N: u64 = %s;\n' "$N" > "$WORK/fib_n.rs"
    if rustc -O --edition 2021 -o "$WORK/fib-rs" "$WORK/fib.rs" \
         > "$WORK/build-rs.log" 2>&1; then
      set +e; "$WORK/fib-rs"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "Rust fib($N)=$GOT, оракул $WANT"
    else
      bad "збірка Rust-близнюка"
      tail -3 "$WORK/build-rs.log"
    fi
  fi

  # Free Pascal: N вшивається через згенерований include
  if have fpc; then
    printf 'const FIB_N = %s;\n' "$N" > "$WORK/fib_n.inc"
    if fpc -B -O2 -Fi"$WORK" -FU"$WORK/u" -FE"$WORK/b" \
         -o"$WORK/fib-pas" "$ROOT/benchmarks/cross-language/fib/fib.pas" \
         > "$WORK/build-pas.log" 2>&1; then
      set +e; "$WORK/fib-pas"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "FPC fib($N)=$GOT, оракул $WANT"
    else
      bad "збірка FPC-близнюка"
      tail -3 "$WORK/build-pas.log"
    fi
  fi

  # Тіло SENS, знижене в x86-64
  "$WORK/b/sensfiblower" "$ROOT" "$N" "$WORK/fib-sens" \
    || { bad "зниження тіла SENS для n=$N"; exit 1; }
  chmod +x "$WORK/fib-sens"
  set +e; "$WORK/fib-sens"; GOT=$?; set -e
  [ "$GOT" = "$WANT" ] || bad "SENS-lowered fib($N)=$GOT, оракул $WANT"

  say "n=$N оракул=$WANT звірено"
done

if [ "$FAIL" -ne 0 ]; then
  echo "FIB-TWINS-FAIL"
  exit 1
fi

if [ "$MEASURE" -eq 1 ]; then
  say "вимірювання: $REPEATS повторів на кожне n (час процесу, не енергія)"
  say "походження: SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  say "CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
  have fpc && say "FPC=$(fpc -iV)"
  have gcc && say "GCC=$(gcc -dumpversion)"
  have rustc && say "RUSTC=$(rustc --version | cut -d' ' -f2)"

  # Час одного запуску в мікросекундах: date +%s%N доступний на Linux.
  measure_one() {
    local bin="$1" start end
    start=$(date +%s%N)
    set +e; "$bin"; set -e
    end=$(date +%s%N)
    echo $(( (end - start) / 1000 ))
  }

  for N in $NS; do
    WANT="$(oracle "$N")"
    # SENS-ELF для цього N
    printf '%s\n' "$N" > "$WORK/n.txt"
    "$WORK/b/test-elffib" > /dev/null 2>&1 || true
    printf 'const FIB_N = %s;\n' "$N" > "$WORK/fib_n.inc"
    fpc -B -O2 -Fi"$WORK" -FU"$WORK/u" -FE"$WORK/b" \
      -o"$WORK/fib-pas" "$ROOT/benchmarks/cross-language/fib/fib.pas" \
      > /dev/null 2>&1
    if have gcc; then
      gcc -O2 -DN="$N" -o "$WORK/fib-c" "$ROOT/benchmarks/cross-language/fib/fib.c"
    fi
    if have rustc; then
      printf 'const N: u64 = %s;\n' "$N" > "$WORK/fib_n.rs"
      rustc -O --edition 2021 -o "$WORK/fib-rs" \
        "$ROOT/benchmarks/cross-language/fib/fib.rs" > /dev/null 2>&1 || true
    fi

    "$WORK/b/sensfiblower" "$ROOT" "$N" "$WORK/fib-sens" > /dev/null 2>&1 || true
    [ -x "$WORK/fib-sens" ] || chmod +x "$WORK/fib-sens" 2>/dev/null || true
    for twin in fib-c fib-rs fib-pas fib-sens; do
      [ -x "$WORK/$twin" ] || continue
      total=0
      for ((r=0; r<REPEATS; r++)); do
        total=$((total + $(measure_one "$WORK/$twin")))
      done
      say "n=$N $twin сер.=$(( total / REPEATS )) мкс"
    done
  done
  say "УВАГА: числа — час процесу, не енергія. Енергія потребує окремого протоколу."
else
  say "вимірювання не запускалося (додайте --measure)"
fi

echo "FIB-TWINS-PASS"
