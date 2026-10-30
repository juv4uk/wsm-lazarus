#!/usr/bin/env bash
# Core1.2: існуючі GC і lexical frames — реальна FPC перевірка.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'Немає FPC' >&2; exit 127; }
mkdir -p build/m0.2/gcclosure-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/gcclosure-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-gcclosure \
  "$ROOT/scripts/test-gcclosure.pas"
"$ROOT/build/m0.2/bin/test-gcclosure" > build/m0.2/gcclosure-test.out \
  2>build/m0.2/gcclosure-heap.err
# ASCII prefix не залежить від обраного stdout кодового набору FPC.
grep -Fq 'GC-CORE1-' build/m0.2/gcclosure-test.out
grep -Fq 'oracle=' build/m0.2/gcclosure-test.out
grep -Fq '0 unfreed memory blocks' build/m0.2/gcclosure-heap.err
if grep -E 'unfreed memory blocks : [1-9]' build/m0.2/gcclosure-heap.err; then
  echo 'GC-CORE1-ПРОВАЛ: HeapTrc зафіксував витік' >&2
  exit 1
fi
# Наявні тести не вимикаємо; test-envframe.sh немає — компілюємо
# чинний scripts/test-envframe.pas у власну unit-директорію.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/gcclosure-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-envframe-gcclosure \
  "$ROOT/scripts/test-envframe.pas"
"$ROOT/build/m0.2/bin/test-envframe-gcclosure"
bash ./scripts/test-gc.sh
cat build/m0.2/gcclosure-test.out
echo 'GC-CORE1-FPC-OK physical=T5M roots=shared-GC'
