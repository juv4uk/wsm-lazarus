#!/usr/bin/env bash
# G6.28: реальна FPC збірка, x86-64 машинний ELF і byte-exact T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЦИТАТА-ЕЛФ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/quotet5m/bin build/m0.2/quotet5m/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/quotet5m/units" \
  -FE"$ROOT/build/m0.2/quotet5m/bin" \
  -otest-elfquote-t5m "$ROOT/scripts/test-elfquote-t5m.pas"
timeout 30s "$ROOT/build/m0.2/quotet5m/bin/test-elfquote-t5m" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/quotet5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in д1-нуль д1-один д3-порожньо д7-керування д9-нулі список вкладений; do
  ELF="build/m0.2/quotet5m/$label.elf"
  EXPECT="build/m0.2/quotet5m/$label.expected.sens"
  test -s "$ELF"
  test -s "$EXPECT"
  chmod u+x "$ELF"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/program"
  grep -F 'ELF64' "$TMP/header" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F 'LOAD' "$TMP/program" >/dev/null
  dd if="$ELF" of="$TMP/code" bs=1 skip=120 count=50 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" > "$TMP/code.asm"
  grep -F 'lea' "$TMP/code.asm" >/dev/null
  grep -F 'rip+' "$TMP/code.asm" >/dev/null
  grep -F 'syscall' "$TMP/code.asm" >/dev/null
  grep -Eiq 'cmp[[:space:]]+rax,rdx' "$TMP/code.asm"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/code.asm"
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$EXPECT"
done
# G6.224: справжні Linux host-I/O негативи на одно- й багатобайтовому
# фізичному T5M, без підміни SENS-оракула або вимкнення старих тестів.
test -c /dev/full
FAILED_WRITE=0
RECOVERED=0
for label in д1-один список; do
  ELF="build/m0.2/quotet5m/$label.elf"
  EXPECT="build/m0.2/quotet5m/$label.expected.sens"
  if [[ "$label" == список ]]; then
    test "$(wc -c < "$EXPECT")" -gt 1
  else
    test "$(wc -c < "$EXPECT")" -eq 1
  fi

  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/closed.stderr" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/closed.stderr"
  FAILED_WRITE=$((FAILED_WRITE+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.stderr" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/full.stderr"
  FAILED_WRITE=$((FAILED_WRITE+1))

  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/recovered.stderr"
  cmp "$EXPECT" "$TMP/recovered.sens"
  test ! -s "$TMP/recovered.stderr"
  RECOVERED=$((RECOVERED+1))
done
test "$FAILED_WRITE" -eq 4 && test "$RECOVERED" -eq 2
echo "ЦИТАТА-ЕЛФ-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 ELF=7 T5M=byte-exact" \
     "write-негативів=$FAILED_WRITE відновлень=$RECOVERED machine=CMP/JNE" 
