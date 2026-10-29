#!/usr/bin/env bash
# Core1.2 — інтеграція НЕ нового GC, а готових wsm.gc + wsm.envframe.
set -euo pipefail
export LANG=C.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
for bin in "$FPC_BIN" timeout grep mktemp; do
  command -v "$bin" >/dev/null || { echo "CORE1-GC-БЛОК: немає $bin" >&2; exit 127; }
done
TMP=$(mktemp -d)
trap 'status=$?; if ((status != 0)); then echo "CORE1-GC-БЛОК: команда=$BASH_COMMAND exit=$status рядок=$LINENO" >&2; for f in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 28 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-core1-roots "$ROOT/scripts/test-core1-roots.pas" >"$TMP/build.log" 2>&1
timeout 30s "$TMP/bin/test-core1-roots" >"$TMP/test.out" 2>"$TMP/test.err"
grep -Fq 'CORE1-GC-КОРЕНІ-ГАРАЗД' "$TMP/test.out"
grep -Fq 'виклики=256' "$TMP/test.out"
# Free Pascal heaptrc може не друкувати нічого при нульовому витоку;
# не вимикаємо -gh, явний ненульовий звіт завжди блокує gate.
if grep -Fq 'unfreed memory blocks' "$TMP/test.err" && \
   ! grep -Eq '(^| )0 unfreed memory blocks' "$TMP/test.err"; then
  echo 'CORE1-GC-ПРОВАЛ: FPC heaptrc зафіксував витік' >&2
  cat "$TMP/test.err" >&2
  exit 1
fi
# Чинні механічні регресії GC/фреймів не пропускаємо.
timeout 180s bash ./scripts/test-gc.sh >"$TMP/gc.log" 2>"$TMP/gc.err"
timeout 90s bash ./scripts/test-envframe-index.sh >"$TMP/env.log" 2>"$TMP/env.err"
echo 'CORE1-GC-МІСТ-ГАРАЗД FPC=3.2.x реальний scope=256 цикли=так stale=відхилено чужий-GC=відхилено gc-регресії=так envframe=так'
