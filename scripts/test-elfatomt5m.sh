#!/usr/bin/env bash
# G6.27 — справжній x86-64 ELF, який повертає рівно T5M фізичний байт.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'АТОМ-T5M-БЛОКЕР: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
command -v timeout >/dev/null

# Доведений pinned gitlink, а не випадково свіжий upstream.
PIN=$(git -C external/sens rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
[[ "$PIN" == "$GITLINK" ]] || {
  echo 'АТОМ-T5M-БЛОКЕР: pinned SENS не збігається з gitlink' >&2; exit 1;
}
mkdir -p build/m0.2/atomt5m/bin build/m0.2/atomt5m/units
# Pinned sparse checkout не містить усіх свідків у файловій системі:
# читаємо точний Git object, НЕ підмінюємо його локальним fixture.
timeout 70s git -C "$ROOT/external/sens" show \
  "$PIN:tests/semantic/d3-eq-atom-boundary-law.sens" \
  > build/m0.2/atomt5m/pinned.sens
test -s build/m0.2/atomt5m/pinned.sens
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/atomt5m/units" \
  -FE"$ROOT/build/m0.2/atomt5m/bin" \
  -otest-elfatomt5m "$ROOT/scripts/test-elfatomt5m.pas"
timeout 45s "$ROOT/build/m0.2/atomt5m/bin/test-elfatomt5m" \
  "$ROOT/external/sens" "$ROOT/build/m0.2/atomt5m"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in атом-нуль атом-один атом-порожній атом-д3-порожній \
  атом-пара атом-пара-порожній атом-пара-пар \
  атом-вкладений-атом-пари атом-атома атом-вкладена-пара; do
  ELF="build/m0.2/atomt5m/$label.elf"
  LEGACY="build/m0.2/atomt5m/$label.legacy.elf"
  test -s "$ELF" && test -s "$LEGACY"
  chmod u+x "$ELF" "$LEGACY"
  readelf -h "$ELF" > "$TMP/header"
  readelf -l "$ELF" > "$TMP/program-headers"
  grep -F ELF64 "$TMP/header" >/dev/null
  grep -E 'Type:.*EXEC' "$TMP/header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/header" >/dev/null
  grep -F 'LOAD' "$TMP/program-headers" >/dev/null
  tail -c +121 "$ELF" > "$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" > "$TMP/disassembly"
  grep -F 'setne' "$TMP/disassembly" >/dev/null
  grep -F 'movzx' "$TMP/disassembly" >/dev/null
  grep -F 'imul' "$TMP/disassembly" >/dev/null
  grep -F 'syscall' "$TMP/disassembly" >/dev/null
  timeout 5s "$ELF" > "$TMP/answer.sens"
  timeout 5s "$LEGACY" > "$TMP/answer.ascii"
  test "$(wc -c < "$TMP/answer.sens")" -eq 1
  cmp "$TMP/answer.sens" "build/m0.2/atomt5m/$label.expected.sens"
  cmp "$TMP/answer.ascii" "build/m0.2/atomt5m/$label.expected.ascii"
done
echo 'АТОМ-T5M-МАШИНА-ГАРАЗД Linux=x86-64 справжній-ELF=10 машинний-ATOM=так T5M=точні-байти негативні=16'
