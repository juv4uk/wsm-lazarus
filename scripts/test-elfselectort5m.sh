#!/usr/bin/env bash
# G6.26 — реальний x86-64 машинний CONS→селектор→T5M (не ASCII).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИННИЙ-СЕЛЕКТОР-T5M-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
command -v "${FPC:-fpc}" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/selectort5m/units build/m0.2/selectort5m/bin
"${FPC:-fpc}" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/selectort5m/units" \
  -FE"$ROOT/build/m0.2/selectort5m/bin" \
  -otest-elfselectort5m "$ROOT/scripts/test-elfselectort5m.pas"
timeout 35s "$ROOT/build/m0.2/selectort5m/bin/test-elfselectort5m" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/selectort5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in перше-00 перше-01 перше-10 перше-11 \
             решта-00 решта-01 решта-10 решта-11; do
  ELF="build/m0.2/selectort5m/$label.elf"
  test -s "$ELF"
  chmod u+x "$ELF"
  readelf -h "$ELF" >"$TMP/head"
  readelf -l "$ELF" >"$TMP/segments"
  grep -F 'ELF64' "$TMP/head" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/head" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/head" >/dev/null
  grep -F 'LOAD' "$TMP/segments" >/dev/null
  if grep -E 'INTERP|DYNAMIC' "$TMP/segments" >/dev/null; then
    echo 'МАШИННИЙ-СЕЛЕКТОР-T5M-БЛОК: сторонній завантажувач' >&2
    exit 1
  fi
  tail -c +121 "$ELF" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/asm"
  grep -F 'QWORD PTR [rsp],rax' "$TMP/asm" >/dev/null
  grep -F 'QWORD PTR [rsp+0x8],rcx' "$TMP/asm" >/dev/null
  grep -F 'QWORD PTR [rsi+0x' "$TMP/asm" >/dev/null
  grep -F 'imul' "$TMP/asm" >/dev/null
  timeout 5s "$ELF" >"$TMP/answer.sens"
  test "$(wc -c <"$TMP/answer.sens")" -eq 1
  cmp "$TMP/answer.sens" "build/m0.2/selectort5m/$label.expected.sens"
  cmp "$TMP/answer.sens" "build/m0.2/selectort5m/$label.native.sens"
done
echo 'МАШИННИЙ-СЕЛЕКТОР-T5M-ФІЗИЧНИЙ-ГАРАЗД FPC=так ELF=8 CONS=2-QWord T5M=byte-exact негативні=11'
