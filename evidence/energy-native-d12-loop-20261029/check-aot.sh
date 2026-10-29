#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
OUT="$ROOT/build/energy/native-d12-loop"

for name in sum-cpp sum-zig sum-fortran sum-swift; do
  file="$OUT/$name"
  if [[ ! -x "$file" ]]; then
    printf 'Немає виконуваного AOT варіанта: %s\n' "$file" >&2
    exit 1
  fi
  set +e
  "$file" 8388361 >/dev/null 2>&1
  code=$?
  set -e
  if [[ $code -ne 173 ]]; then
    printf 'Хибний результат %s: очікувався код 173, отримано %s\n' "$file" "$code" >&2
    exit 1
  fi
  set +e
  "$file" >/dev/null 2>&1
  code=$?
  set -e
  if [[ $code -ne 64 ]]; then
    printf 'Хибна перевірка аргументів %s: очікувався код 64, отримано %s\n' "$file" "$code" >&2
    exit 1
  fi
done

printf 'AOT-ПАРИТЕТ-ПЕРЕВІРКА-ГАРАЗД: 4 варіанти, exit=173\n'
