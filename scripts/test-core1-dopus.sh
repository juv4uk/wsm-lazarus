#!/usr/bin/env bash
# Core1.1 — реальний FPC допуск pinned .sens і української .lisp.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE1-ДОПУСК-БЛОК: FPC відсутній' >&2; exit 127; }
mkdir -p build/m0.2/core1-dopus-units build/m0.2/core1-dopus-bin
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core1-dopus-units" \
  -FE"$ROOT/build/m0.2/core1-dopus-bin" \
  -osenscore1dopus "$ROOT/src/senscore1dopus.lpr"
CLI="$ROOT/build/m0.2/core1-dopus-bin/senscore1dopus"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 60s "$CLI" --допуск "$ROOT" >"$TMP/справжній" 2>"$TMP/справжній.err"
timeout 60s "$CLI" --допуск "$ROOT" >"$TMP/повтор" 2>"$TMP/повтор.err"
cmp "$TMP/справжній" "$TMP/повтор"
grep -Fq 'CORE1-ДОПУСК-ГАРАЗД форм-укр=' "$TMP/справжній"
grep -Fq 'T5M=побайтово виконання=ні' "$TMP/справжній"
grep -Eq 'форм-фізично=[1-9][0-9]*' "$TMP/справжній"
test ! -s "$TMP/справжній.err"
mkdir -p "$TMP/чужий/external/sens/lib"
cp "$ROOT/external/sens/lib/core1.sens" "$TMP/чужий/external/sens/lib/core1.sens"
cp "$ROOT/external/sens/lib/core1.lisp" "$TMP/чужий/external/sens/lib/core1.lisp"
reject() {
  if timeout 60s "$CLI" "$@" >"$TMP/частковий.stdout" 2>"$TMP/помилка.stderr"; then
    echo 'CORE1-ДОПУСК-ПРОВАЛ: хибний файл прийнято' >&2; exit 1
  fi
  test ! -s "$TMP/частковий.stdout" || {
    echo 'CORE1-ДОПУСК-ПРОВАЛ: частковий stdout' >&2; exit 1
  }
  grep -Fq 'CORE1-ДОПУСК-ВІДМОВА:' "$TMP/помилка.stderr" || {
    cat "$TMP/помилка.stderr" >&2; exit 1
  }
}
reject --допуск "$TMP/немає"
printf '\377' >>"$TMP/чужий/external/sens/lib/core1.sens"
reject --допуск "$TMP/чужий"
cp "$ROOT/external/sens/lib/core1.sens" "$TMP/чужий/external/sens/lib/core1.sens"
printf '\300\257' >"$TMP/чужий/external/sens/lib/core1.lisp"
reject --допуск "$TMP/чужий"
: >"$TMP/чужий/external/sens/lib/core1.lisp"
reject --допуск "$TMP/чужий"
cp "$ROOT/external/sens/lib/core1.lisp" "$TMP/чужий/external/sens/lib/core1.lisp"
printf '\n(як-є ())\n' >>"$TMP/чужий/external/sens/lib/core1.lisp"
reject --допуск "$TMP/чужий"
cp "$ROOT/external/sens/lib/core1.lisp" "$TMP/чужий/external/sens/lib/core1.lisp"
: >"$TMP/чужий/external/sens/lib/core1.sens"
reject --допуск "$TMP/чужий"
timeout 60s "$CLI" --допуск "$ROOT" >"$TMP/після"
cmp "$TMP/справжній" "$TMP/після"
echo 'CORE1-ДОПУСК-ТЕСТ-ГАРАЗД pinned=так фізичний=так укр=так негативні=6 відновлення=так виконання=ні'
