#!/usr/bin/env bash
# G6.233 — фізичний D12 ADD→IMUL→T5M: host Linux stdout має бути повним.
# Це регресійна машинна перевірка наявного AOT, НЕ новий закон SENS.
# FPC зберігає managed RawByteString fixtures; ELF використовує приватний
# стековий T5M-буфер до sys_exit, жодного GC чи GUI тут немає.
# 1) Чому перевірка stdout не є SENS семантикою?
# 2) Чому успішний exit вимагає рівно 3 або 5 фізичних T5M байтів?
# 3) Чому /dev/full перевіряє ENOSPC, а не числове переповнення D12?
# 4) Чому повторний запуск потрібен після негативної перевірки?
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-КОМПОЗИЦІЯ-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "Д12-КОМПОЗИЦІЯ-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
FPC_BIN=$(printenv FPC || echo fpc)
for entry in \
  'scripts/test-elfd12addmul.pas test-elfd12addmul' \
  'src/sensd12addmul-elf.lpr sensd12addmul-elf'; do
  read -r source exe <<< "$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.log" 2>&1; then
    cat "$TMP/$exe.log" >&2
    exit 1
  fi
  test -x "$TMP/bin/$exe"
done
timeout 15s "$TMP/bin/test-elfd12addmul" "$TMP/cases" \
  >"$TMP/matrix.tsv" 2>"$TMP/fixture.log"
grep -Fq 'D12-КОМПОЗИЦІЯ-СВІДКИ-ГАРАЗД пар=12' "$TMP/fixture.log"
[[ $(wc -l <"$TMP/matrix.tsv") -eq 12 ]]
MODE=--додати-потім-помножити-D12
PASS=0
BAD=0
RECOVERED=0
WIDE=0
while IFS=$'\t' read -r label a b c width; do
  [[ -n "$label" && ( "$width" == 12 || "$width" == 24 ) ]]
  if [[ "$width" == 24 ]]; then WIDE=$((WIDE+1)); fi
  timeout 15s "$TMP/bin/sensd12addmul-elf" "$MODE" \
    "$TMP/cases/$label-a.sens" "$TMP/cases/$label-b.sens" \
    "$TMP/cases/$label-c.sens" "$TMP/$label.elf" \
    >"$TMP/compiler.log" 2>"$TMP/compiler.err"
  test ! -s "$TMP/compiler.err"
  grep -Fq 'D12-ОДИН-ELF-ГОТОВО' "$TMP/compiler.log"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/header"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  tail -c +121 "$TMP/$label.elf" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" >"$TMP/disassembly"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/disassembly"
  grep -Eiq 'imul[[:space:]]+eax,' "$TMP/disassembly"
  timeout 5s "$TMP/$label.elf" >"$TMP/output.sens" 2>"$TMP/error"
  test ! -s "$TMP/error"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/output.sens"
  if [[ "$width" == 12 ]]; then [[ $(wc -c <"$TMP/output.sens") -eq 3 ]]
  else [[ $(wc -c <"$TMP/output.sens") -eq 5 ]]; fi
  PASS=$((PASS+1))
  for destination in closed full; do
    rc=0
    if [[ "$destination" == closed ]]; then
      timeout 5s "$TMP/$label.elf" 1>&- 2>"$TMP/error" || rc=$?
    else
      timeout 5s "$TMP/$label.elf" > /dev/full 2>"$TMP/error" || rc=$?
    fi
    # Host exit=2: машинний sys_write не записав усі фізичні T5M байти.
    [[ "$rc" -eq 2 ]]
    test ! -s "$TMP/error"
    BAD=$((BAD+1))
  done
  timeout 5s "$TMP/$label.elf" >"$TMP/again.sens" 2>"$TMP/error"
  test ! -s "$TMP/error"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/again.sens"
  RECOVERED=$((RECOVERED+1))
done <"$TMP/matrix.tsv"
[[ "$PASS" -eq 12 && "$BAD" -eq 24 && "$RECOVERED" -eq 12 && "$WIDE" -ge 2 ]]
echo "Д12-КОМПОЗИЦІЯ-WRITE-ГАРАЗД positives=$PASS negatives=$BAD recovery=$RECOVERED D24=$WIDE energy=НЕ-ВИМІРЯНО"
