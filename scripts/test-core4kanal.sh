#!/usr/bin/env bash
# G5.22: фізичний бінарний Core4 host канал із реальним FPC.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=fpc
command -v "$FPC_BIN" >/dev/null || { echo 'КАНАЛ-БЛОКЕР: немає FPC' >&2; exit 127; }
BIN="$ROOT/build/m0.2/bin"
UNITS="$ROOT/build/m0.2/core4-kanal-units"
mkdir -p "$BIN" "$UNITS"
for entry in src/senscore4kanal.lpr scripts/test-core4kanal.pas; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "$ROOT/$entry"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! "$BIN/test-core4kanal" generate "$ROOT" "$TMP" >"$TMP/generate.out" 2>"$TMP/generate.err"; then
  echo 'КАНАЛ-ПОМИЛКА: фізичні pinned свідки не згенеровано' >&2
  cat "$TMP/generate.err" >&2
  exit 1
fi
# На RED покажемо реальний stdout/stderr генератора, не ховаючи діагностику.
cat "$TMP/generate.out"
cat "$TMP/generate.err" >&2
grep -Fq 'КАНАЛ-СВІДКИ-ГОТОВО' "$TMP/generate.out"
grep -Fq '0 unfreed memory blocks' "$TMP/generate.err"
C="$BIN/senscore4kanal"
run_expect() {
  local name="$1" expected="$2" result="$3" rc=0
  "$C" --канал "$ROOT" <"$TMP/$name.bin" >"$TMP/$result" 2>"$TMP/$name.err" || rc=$?
  if [[ "$rc" -ne "$expected" ]]; then
    echo "КАНАЛ-ПОМИЛКА $name: код $rc замість $expected" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  fi
  echo "КАНАЛ-ЗАПУСК $name код=$rc байти=$(wc -c <"$TMP/$result")"
  if ! grep -Fq '0 unfreed memory blocks' "$TMP/$name.err"; then
    echo "КАНАЛ-ПОМИЛКА: heaptrc не підтверджено для $name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  fi
}
run_expect запити 2 відповіді.bin
run_expect один 0 один-відповідь.bin
run_expect обрізано-заголовок 2 обрізано-заголовок-відповідь.bin
run_expect обрізано-дані 2 обрізано-дані-відповідь.bin
run_expect завеликий 2 завеликий-відповідь.bin
run_expect неповний 2 неповний-відповідь.bin
run_expect пустий 0 пустий-відповідь.bin
test ! -s "$TMP/завеликий-відповідь.bin"
test ! -s "$TMP/неповний-відповідь.bin"
test ! -s "$TMP/пустий-відповідь.bin"
for name in обрізано-дані обрізано-заголовок завеликий; do
  if ! grep -Fq 'ПОМИЛКА ФІЗИЧНОГО КАНАЛУ:' "$TMP/$name.err"; then
    echo "КАНАЛ-ПОМИЛКА: відсутня очікувана діагностика $name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  fi
done
echo 'КАНАЛ-ЗВІРКА-СТАРТ'
if ! "$BIN/test-core4kanal" verify "$ROOT" "$TMP" >"$TMP/verify.out" 2>"$TMP/verify.err"; then
  echo 'КАНАЛ-ПОМИЛКА: байтовий валідатор відхилив відповіді' >&2
  cat "$TMP/verify.err" >&2
  exit 1
fi
cat "$TMP/verify.out"
cat "$TMP/verify.err" >&2
grep -Fq 'КАНАЛ-ПЕРЕВІРЕНО' "$TMP/verify.out"
grep -Fq '0 unfreed memory blocks' "$TMP/verify.err"
rc=0
"$C" --канал "$TMP/немає-кореня" </dev/null >"$TMP/no-root.out" 2>"$TMP/no-root.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/no-root.out"
rc=0
"$C" --не-канал "$ROOT" </dev/null >"$TMP/invalid.out" 2>"$TMP/invalid.err" || rc=$?
test "$rc" -eq 64
test ! -s "$TMP/invalid.out"
echo 'CORE4-КАНАЛ-ГАРАЗД FPC=справжній runtime=один кадри=8 негативні=3 EOF=чистий обрив=fail-closed D12+=без-числового-допуску REPL=ні'
