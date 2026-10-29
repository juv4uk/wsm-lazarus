#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
OUT="$ROOT/build/energy/native-d12-loop"
mkdir -p "$OUT/fpc-units"

python3 - "$OUT/sens-native.elf" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink(missing_ok=True)
PY

timeout 180s fpc -B -Cr -Co -Ci -Mobjfpc -Fu"$ROOT/src" \
  -FU"$OUT" -FE"$OUT" -obuild-sens-loop \
  "$HERE/build-sens-loop.pas"
"$OUT/build-sens-loop" "$OUT/sens-native"
chmod +x "$OUT/sens-native.elf"

gcc -std=c11 -O2 -Wall -Wextra -Werror \
  "$HERE/sum.c" -o "$OUT/sum-c"
RUSTC=${RUSTC:-rustc}
"$RUSTC" --edition=2021 -C opt-level=2 -C codegen-units=1 \
  "$HERE/sum.rs" -o "$OUT/sum-rust"
timeout 180s fpc -B -O2 -Mobjfpc -FU"$OUT/fpc-units" -FE"$OUT" \
  -osum-fpc "$HERE/sum.pas"

for file in "$OUT/sens-native.elf" "$OUT/sum-c" "$OUT/sum-rust" "$OUT/sum-fpc"; do
  set +e
  if [[ "$file" == "$OUT/sens-native.elf" ]]; then
    "$file" >/dev/null 2>&1
  else
    "$file" 8388361 >/dev/null 2>&1
  fi
  code=$?
  set -e
  if [[ $code -ne 173 ]]; then
    printf 'Хибний результат %s: очікувався код 173, отримано %s\n' "$file" "$code" >&2
    exit 1
  fi
done
printf 'D12-ЦИКЛ-ЗБІРКА-ГАРАЗД N=8388361 exit=173\n'
