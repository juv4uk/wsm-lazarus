#!/usr/bin/env bash
# G6.29: реальне Free Pascal -> перевірений ExactIR -> Linux ELF64 -> T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ДОВІРЕНИЙ-IR-ЕЛФ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/exactirtoelf/bin build/m0.2/exactirtoelf/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/exactirtoelf/units" \
  -FE"$ROOT/build/m0.2/exactirtoelf/bin" \
  -otest-exactirtoelf "$ROOT/scripts/test-exactirtoelf.pas"
timeout 30s "$ROOT/build/m0.2/exactirtoelf/bin/test-exactirtoelf" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/exactirtoelf"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOST_BAD=0; RECOVERED=0; GOOD=0
for label in д1-нуль д1-один д3-порожньо д7-син д7-мінімум \
  д7-максимум д7-бітовий д9-нулі список вкладений; do
  ELF="build/m0.2/exactirtoelf/$label.elf"
  EXPECT="build/m0.2/exactirtoelf/$label.expected.sens"
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
  grep -Eiq 'jne[[:space:]]' "$TMP/code.asm"
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$EXPECT"
  GOOD=$((GOOD+1))
  # Відмови host-публікації НЕ є значенням SENS. Для кожного
  # фізичного D1/D7/D9/списку необхідний Linux exit(2).
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.err"
  HOST_BAD=$((HOST_BAD+1))
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.err"
  HOST_BAD=$((HOST_BAD+1))
  timeout 5s "$ELF" > "$TMP/recovered.sens" 2>"$TMP/recovered.err"
  test ! -s "$TMP/recovered.err"
  cmp "$TMP/recovered.sens" "$EXPECT"
  RECOVERED=$((RECOVERED+1))
done
test "$GOOD" -eq 10 && test "$HOST_BAD" -eq 20 && test "$RECOVERED" -eq 10
echo "ДОВІРЕНИЙ-IR-ЕЛФ-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 ELF=$GOOD T5M=byte-exact write-відмов=$HOST_BAD відновлень=$RECOVERED"
