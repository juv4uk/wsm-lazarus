#!/usr/bin/env bash
# Core1: лише реальні механізми лексичного середовища та наявного GC.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'CORE1-GC-ПОМИЛКА: немає FPC' >&2; exit 127; }
mkdir -p build/core1-gccapture/units build/core1-gccapture/bin
for source in scripts/test-core1-gccapture.pas scripts/test-envframe.pas scripts/test-gc.pas scripts/test-gc-scopes.pas; do
  fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/core1-gccapture/units" \
    -FE"$ROOT/build/core1-gccapture/bin" "$source"
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
build/core1-gccapture/bin/test-core1-gccapture > "$TMP/ours.out"
grep -Fq 'CORE1-GC-ЗАХОПЛЕННЯ-ГАРАЗД' "$TMP/ours.out"
grep -Fq 'повтори=64' "$TMP/ours.out"
grep -Fq 'семантика-Core1=ЩЕ-НЕ-ВИКОНАНО' "$TMP/ours.out"
build/core1-gccapture/bin/test-envframe > "$TMP/env.out"
grep -Fq 'ENVFRAME-OK' "$TMP/env.out"
build/core1-gccapture/bin/test-gc > "$TMP/gc.out"
grep -Fq 'GC-' "$TMP/gc.out"
build/core1-gccapture/bin/test-gc-scopes > "$TMP/scopes.out"
test -s "$TMP/scopes.out"
cat "$TMP/ours.out"
echo 'CORE1-GC-FPC-ГАРАЗД нативний-GC=так середовище=так семантика-Core1=ЩЕ-НЕ-ВИКОНАНО'
