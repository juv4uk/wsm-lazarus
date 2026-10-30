#!/usr/bin/env bash
# G6.64 — реальний FPC, виконання ELF64 та фізичні T5M свідки.
set -euxo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo "ПРЯМИЙ-АТОМ-БЛОК: потрібен Linux x86-64" >&2; exit 127; }
for cmd in fpc timeout readelf objdump cmp mktemp; do command -v "$cmd" >/dev/null || exit 127; done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-exactir-atom-priamyi "$ROOT/scripts/test-exactir-atom-priamyi.pas" >"$TMP/fpc.log" 2>&1 || { cat "$TMP/fpc.log" >&2; exit 1; }
timeout 90s "$TMP/bin/test-exactir-atom-priamyi" "$ROOT/external/sens" "$TMP/cases" >"$TMP/report.log" 2>"$TMP/error.log" || { cat "$TMP/report.log" >&2; cat "$TMP/error.log" >&2; echo "ПРЯМИЙ-АТОМ-БЛОК: FPC тест невдалий" >&2; exit 1; }
grep -Fq 'ПРЯМИЙ-АТОМ-ГАРАЗД' "$TMP/report.log" || { echo "ПРЯМИЙ-АТОМ-БЛОК: FPC позитивний тест не опублікував маркер" >&2; cat "$TMP/report.log" >&2; cat "$TMP/error.log" >&2; exit 1; }
POS=0; HOST_BAD=0; RECOVERED=0
for name in д1-нуль д1-один д1-відновлено; do
  elf="$TMP/cases/$name.elf"
  chmod u+x "$elf"
  readelf -h "$elf" > "$TMP/header"
  grep -Fq ELF64 "$TMP/header"
  grep -Eq 'Type:.*EXEC' "$TMP/header"
  tail -c +121 "$elf" > "$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" > "$TMP/disassembly"
  grep -Fq setne "$TMP/disassembly"
  grep -Fq movzx "$TMP/disassembly"
  # Спільний ET_EXEC guard: JMP rel32 веде до CMP EAX,EDX / SETNE DIL.
  tail -c 11 "$elf" >"$TMP/epilogue.bin"
  printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' >"$TMP/expected-epilogue.bin"
  cmp "$TMP/epilogue.bin" "$TMP/expected-epilogue.bin"
  timeout 5s "$elf" > "$TMP/answer.sens"
  cmp "$TMP/answer.sens" "$TMP/cases/$name.expected.sens"
  POS=$((POS+1))
  rc=0
  timeout 5s "$elf" 1>&- 2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed.err"
  HOST_BAD=$((HOST_BAD+1))
  rc=0
  timeout 5s "$elf" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full.err"
  HOST_BAD=$((HOST_BAD+1))
  timeout 5s "$elf" >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
  test ! -s "$TMP/recovered.err"
  cmp "$TMP/recovered.sens" "$TMP/cases/$name.expected.sens"
  RECOVERED=$((RECOVERED+1))
done
test "$POS" -eq 3 && test "$HOST_BAD" -eq 6 && test "$RECOVERED" -eq 3
timeout 300s bash ./scripts/test-exactir-atom-elf.sh
echo "ПРЯМИЙ-АТОМ-ТЕСТ-ГАРАЗД FPC=так машинні-ELF=$POS ExactIR=так T5M=побайтово write-відмов=$HOST_BAD відновлень=$RECOVERED"
