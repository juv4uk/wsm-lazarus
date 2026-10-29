#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT="$ROOT/build/energy/compare"
RUSTC=${RUSTC:-rustc}
mkdir -p "$OUT"
gcc -std=c11 -O2 -Wall -Wextra -Werror \
  "$ROOT/scripts/energy/compare/equal.c" -o "$OUT/equal-c"
"$RUSTC" --edition=2021 -C opt-level=2 -C codegen-units=1 \
  "$ROOT/scripts/energy/compare/equal.rs" -o "$OUT/equal-rust"
fpc -B -O2 -Mobjfpc -FU"$OUT" -FE"$OUT" \
  -o"$OUT/equal-fpc" "$ROOT/scripts/energy/compare/equal.pas"
for name in equal-c equal-rust equal-fpc; do
  response=$(printf '1\n17\n100000\n' | "$OUT/$name")
  test "$response" = "$(printf 'READY\nOK\t1\t161\nOK\t17\t2737\nOK\t100000\t16100000')"
  if printf '0\n' | "$OUT/$name" >/dev/null 2>&1; then
    printf 'Виконавець %s прийняв нульову кількість\n' "$name" >&2
    exit 1
  fi
done
printf 'Готові C, Rust і FPC виконавці рівності.\n'

# Питання: чому всі збірки завершуються до замірів? Які оптимізації спільні?
# Що перевіряє smoke-запуск? Чому версія Rust задана локальним шляхом?
