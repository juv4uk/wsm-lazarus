#!/usr/bin/env bash
# G6.39 — FPC 3.2.2, вісім фізичних D3:100/011 → ExactIR → ELF64.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ДОВІРЕНИЙ-СЕЛЕКТОР-IR-БЛОК: потрібна Linux x86-64' >&2;exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null

# Першоджерело восьми .sens input і незалежного фізичного T5M witness:
# вже наявний генератор, який не змінюємо і не дублюємо.
timeout 150s bash ./scripts/test-elfselectort5m.sh
BASE="$ROOT/build/m0.2/selectort5m"
OUT="$ROOT/build/m0.2/exactirselector"
mkdir -p "$OUT/units" "$OUT/bin" "$OUT/verified"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-exactir-selector "$ROOT/scripts/test-exactir-selector.pas"
timeout 45s "$OUT/bin/test-exactir-selector" \
  "$ROOT/external/sens" "$BASE" "$OUT/verified"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
count=0
for name in перше-00 перше-01 перше-10 перше-11 \
            решта-00 решта-01 решта-10 решта-11; do
  elf="$OUT/verified/$name.elf"
  test -s "$elf"
  cmp "$elf" "$BASE/$name.elf"
  chmod u+x "$elf"
  readelf -h "$elf" >"$TMP/head"
  readelf -l "$elf" >"$TMP/segments"
  grep -F ELF64 "$TMP/head" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/head" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/head" >/dev/null
  grep -F LOAD "$TMP/segments" >/dev/null
  ! grep -E 'INTERP|DYNAMIC' "$TMP/segments" >/dev/null
  tail -c +121 "$elf" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/asm"
  grep -F 'QWORD PTR [rsp],rax' "$TMP/asm" >/dev/null
  grep -F 'QWORD PTR [rsp+0x8],rcx' "$TMP/asm" >/dev/null
  grep -F 'imul' "$TMP/asm" >/dev/null
  timeout 5s "$elf" >"$TMP/answer.sens"
  cmp "$TMP/answer.sens" "$BASE/$name.expected.sens"
  cmp "$TMP/answer.sens" "$BASE/$name.native.sens"
  test "$(wc -c <"$TMP/answer.sens")" -eq 1
  count=$((count+1))
done
test "$count" -eq 8
echo 'ДОВІРЕНИЙ-СЕЛЕКТОР-IR-ФІЗИЧНИЙ-ГАРАЗД ELF64=8 CONS=2QWord T5M=byte-exact'
# Уже наявний provenance guard мусить лишитися придатним для всіх
# чотирьох інших машинних голів D3:001/010/101/110.
timeout 160s bash ./scripts/test-exactir-cond.sh
echo 'ДОВІРЕНИЙ-СЕЛЕКТОР-IR-РЕГРЕСІЯ-ГАРАЗД D3:001/010/011/100/101/110'
