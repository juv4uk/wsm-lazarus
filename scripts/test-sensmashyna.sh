#!/usr/bin/env bash
# G6.31: справжня машина після FPC, byte-exact T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'МАШИНА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p build/m0.2/mashyna/units build/m0.2/mashyna/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/mashyna/units" \
  -FE"$ROOT/build/m0.2/mashyna/bin" -osensmashyna "$ROOT/src/sensmashyna.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/mashyna/units" \
  -FE"$ROOT/build/m0.2/mashyna/bin" -otest-sensmashyna \
  "$ROOT/scripts/test-sensmashyna.pas"
CLI="$ROOT/build/m0.2/mashyna/bin/sensmashyna"
timeout 30s "$ROOT/build/m0.2/mashyna/bin/test-sensmashyna" \
  "$ROOT/external/sens" "$TMP"
PASS=0
for entry in \
  'цитата:цитата-д7' 'цитата:цитата-список' \
  'атом:атом-один' 'атом:атом-пара' \
  'тотожність:тотожні-00' 'тотожність:тотожні-01' \
  'тотожність:тотожні-10' 'тотожність:тотожні-11'; do
  MODE=$(printf '%s' "$entry" | cut -d: -f1)
  LABEL=$(printf '%s' "$entry" | cut -d: -f2)
  ELF="$TMP/$LABEL.elf"
  timeout 10s "$CLI" "--$MODE" "$ROOT/external/sens" "$TMP/$LABEL.sens" "$ELF"
  test -x "$ELF"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/program"
  grep -F 'ELF64' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F 'LOAD' "$TMP/program" >/dev/null
  timeout 5s "$ELF" > "$TMP/виконане.sens"
  cmp "$TMP/виконане.sens" "$TMP/$LABEL.expected.sens"
  PASS=$((PASS+1))
done
tail -c +121 "$TMP/тотожні-00.elf" > "$TMP/code"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" > "$TMP/асемблер"
grep -qi 'sete' "$TMP/асемблер"
tail -c +121 "$TMP/атом-пара.elf" > "$TMP/code"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" > "$TMP/асемблер"
grep -Eqi 'setne|movzx' "$TMP/асемблер"
NEG=0
reject() {
  local out="$TMP/відмовлено.elf"
  rm -f "$out"
  if timeout 12s "$CLI" "$@" "$out" >"$TMP/stdout" 2>"$TMP/stderr"; then
    echo 'МАШИНА-ПОМИЛКА: прийнято неправильний випадок' >&2; exit 1
  fi
  test ! -e "$out"
  test ! -s "$TMP/stdout"
  grep -F 'ELF-' "$TMP/stderr" >/dev/null
  NEG=$((NEG+1))
}
reject --цитата "$ROOT/external/sens" "$TMP/тотожні-00.sens"
reject --атом "$ROOT/external/sens" "$TMP/цитата-д7.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/атом-пара.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/помилковий-байт.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/незакрита-форма.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/хибний-д12.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/порожній.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/немає.sens"
reject --неіснуючий "$ROOT/external/sens" "$TMP/тотожні-00.sens"
cp "$TMP/тотожні-00.elf" "$TMP/незмінний.elf"
if timeout 10s "$CLI" --тотожність "$ROOT/external/sens" \
  "$TMP/тотожні-00.sens" "$TMP/незмінний.elf" >"$TMP/stdout" 2>"$TMP/stderr"; then
  echo 'МАШИНА-ПОМИЛКА: перезапис прийнято' >&2; exit 1
fi
cmp "$TMP/незмінний.elf" "$TMP/тотожні-00.elf"
test ! -s "$TMP/stdout"
NEG=$((NEG+1))
cp "$TMP/тотожні-00.sens" "$TMP/фальшивий.lisp"
reject --тотожність "$ROOT/external/sens" "$TMP/фальшивий.lisp"
test "$PASS" -eq 8
test "$NEG" -eq 11
echo "НАТИВНА-МАШИНА-ГАРАЗД ELF=$PASS негативні=$NEG stdout=T5M D7=точний D12=відхилено"
