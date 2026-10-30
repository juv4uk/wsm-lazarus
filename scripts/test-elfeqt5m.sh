#!/usr/bin/env bash
# G6.25 — реальний ELF Linux x86-64 має вивести канонічний .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-T5M-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
mkdir -p build/m0.2/eqt5m/bin build/m0.2/eqt5m/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src"   -FU"$ROOT/build/m0.2/eqt5m/units"   -FE"$ROOT/build/m0.2/eqt5m/bin"   -otest-elfeqt5m "$ROOT/scripts/test-elfeqt5m.pas"
timeout 30s "$ROOT/build/m0.2/eqt5m/bin/test-elfeqt5m"   "$ROOT/external/sens" "$ROOT/build/m0.2/eqt5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in нуль-нуль нуль-один один-нуль один-один; do
  ELF="build/m0.2/eqt5m/$label.elf"
  test -s "$ELF"
  chmod u+x "$ELF"
  readelf -h "$ELF" >"$TMP/elf-header"
  readelf -l "$ELF" >"$TMP/elf-phdr"
  grep -F 'ELF64' "$TMP/elf-header" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/elf-header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/elf-header" >/dev/null
  grep -F 'LOAD' "$TMP/elf-phdr" >/dev/null
  tail -c +121 "$ELF" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/code.asm"
  grep -F 'sete' "$TMP/code.asm" >/dev/null
  grep -F 'movzx' "$TMP/code.asm" >/dev/null
  grep -F 'imul' "$TMP/code.asm" >/dev/null
  # Перевірка фактичної машинної інструкції CMP EAX,EDX та гілки JNE.
  grep -Eq 'cmp[[:space:]]+eax,edx' "$TMP/code.asm"
  grep -Eq 'jne[[:space:]]' "$TMP/code.asm"
  timeout 5s "$ELF" >"$TMP/answer.sens"
  test "$(wc -c <"$TMP/answer.sens")" -eq 1
  cmp "$TMP/answer.sens" "build/m0.2/eqt5m/$label.expected.sens"
  # Host-негатив: syscall write(1,...) за закритого fd повертає -EBADF.
  # Програма MUST exit(2), а не мовчки exit(0); потім перевірити recovery.
  # 1. Чому це тест syscall, а не семантики D3?
  # 2. Чому важливо перевіряти код 2, а не довільний ненульовий?
  # 3. Чому stderr не повинен містити Pascal/host діагностику?
  # 4. Чому recovery повинен бути побайтово тотожним попередньому ELF?
  RC=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/closed.err" || RC=$?
  test "$RC" -eq 2
  test ! -s "$TMP/closed.err"
  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
  test ! -s "$TMP/recovered.err"
  cmp "$TMP/recovered.sens" "build/m0.2/eqt5m/$label.expected.sens"
done
echo 'ЕЛФ-T5M-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 справжній-ELF=4 CMP/SETE=так T5M=byte-exact admission-негативні=9 fd1-closed=4 recovery=4'
