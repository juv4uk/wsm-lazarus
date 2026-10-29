#!/usr/bin/env bash
# G6.138 — ті самі чотири fib(n), справжній SENS D24 lowerer і RAPL.
# Порівняння по одному хосту, без підміни часу енергією.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
MODE="${1:---verify}"
N="${FIB_N:-35}"
REPEATS="${FIB_REPEATS:-5}"
[[ "$MODE" == --verify || "$MODE" == --measure ]] || {
  echo "Вжиток: scripts/run-fib-energy-cross.sh [--verify|--measure]" >&2; exit 2;
}
[[ "$N" =~ ^[0-9]+$ ]] && (( N >= 10 && N <= 40 )) || {
  echo "FIB-CROSS-ВІДМОВА: N має бути 10..40" >&2; exit 2;
}
[[ "$REPEATS" =~ ^[0-9]+$ ]] && (( REPEATS >= 1 && REPEATS <= 50 )) || {
  echo "FIB-CROSS-ВІДМОВА: REPEATS має бути 1..50" >&2; exit 2;
}
for command_name in fpc gcc rustc python3 git timeout; do
  command -v "$command_name" >/dev/null || {
    echo "FIB-CROSS-ВІДМОВА: потрібен $command_name" >&2; exit 2;
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo "FIB-CROSS-ВІДМОВА: потрібен Linux x86-64" >&2; exit 2;
}
timeout 60s ./scripts/check-pin.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/units" "$WORK/bin"
FPC_BIN=$(printenv FPC || echo fpc)

# Окремо компілюємо кожен з чотирьох реальних виконуваних близнюків.
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$WORK/units" -FE"$WORK/bin" \
  -osensfiblower "$ROOT/src/sensfiblower.lpr" >"$WORK/lower-build.log" 2>&1 || {
    tail -n 20 "$WORK/lower-build.log" >&2; exit 1;
  }
timeout 30s "$WORK/bin/sensfiblower" "$ROOT" "$N" "$WORK/fib-sens"
chmod 0700 "$WORK/fib-sens"

timeout 120s gcc -O2 -DN="$N" \
  -o "$WORK/fib-c" "$ROOT/benchmarks/cross-language/fib/fib.c"
printf 'const FIB_N = %s;\n' "$N" >"$WORK/fib_n.inc"
timeout 180s "$FPC_BIN" -B -O2 -Fi"$WORK" \
  -FU"$WORK/units" -FE"$WORK/bin" -o"$WORK/fib-fpc" \
  "$ROOT/benchmarks/cross-language/fib/fib.pas" >"$WORK/fpc-build.log" 2>&1 || {
    tail -n 20 "$WORK/fpc-build.log" >&2; exit 1;
  }
cp "$ROOT/benchmarks/cross-language/fib/fib.rs" "$WORK/fib.rs"
printf 'const N: u64 = %s;\n' "$N" >"$WORK/fib_n.rs"
timeout 180s rustc --edition 2021 -O -o "$WORK/fib-rust" "$WORK/fib.rs"

# Незалежна перевірка математичного результату, без Pascal/host dispatch.
A=0 B=1
for (( i=0; i<N; i++ )); do T=$((A+B)); A=$B; B=$T; done
WANT=$((A & 255))
ARGS=(--expected "$WANT" --repeats "$REPEATS" \
  --program "SENS=$WORK/fib-sens" --program "C=$WORK/fib-c" \
  --program "RUST=$WORK/fib-rust" --program "FPC=$WORK/fib-fpc")
timeout 240s python3 "$ROOT/scripts/run-fib-energy-cross.py" \
  --verify-only "${ARGS[@]}" || exit 2

printf 'FIB-CROSS-ПОХОДЖЕННЯ sha=%s n=%s cpu=%s\n' \
  "$(git rev-parse HEAD)" "$N" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
printf 'FIB-CROSS-КОМПІЛЯТОРИ fpc=%s gcc=%s rustc=%s\n' \
  "$("$FPC_BIN" -iV)" "$(gcc -dumpfullversion)" "$(rustc --version)"
if [[ "$MODE" == --verify ]]; then
  echo 'FIB-CROSS-BUILD-PASS programs=4 oracle=4 energy=NOT-MEASURED'
else
  # НІЯКИХ мок-лічильників: цей шлях може друкувати тільки реальний RAPL.
  timeout 1200s python3 "$ROOT/scripts/run-fib-energy-cross.py" "${ARGS[@]}"
fi
