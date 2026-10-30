#!/usr/bin/env bash
# Механічна x86-64 перевірка, НЕ незалежний семантичний SENS oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-АСМ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout grep readelf mktemp; do
  command -v "$tool" >/dev/null || { echo "Д12-АСМ-БЛОК: немає $tool" >&2; exit 127; }
done
test "$(fpc -iV)" = '3.2.2' || {
  echo 'Д12-АСМ-БЛОК: потрібен FPC 3.2.2' >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for OPT in O1 O2; do
  mkdir -p "$TMP/$OPT/units" "$TMP/$OPT/bin"
  timeout 120s fpc -B -Mobjfpc -Cr -Co -Ci -gl -"$OPT" \
    -FU"$TMP/$OPT/units" -FE"$TMP/$OPT/bin" -otest-znak \
    "$ROOT/scripts/test-d12-znak-asm.pas" >"$TMP/$OPT/build.log" 2>&1 || {
    cat "$TMP/$OPT/build.log" >&2; exit 1;
  }
  readelf -h "$TMP/$OPT/bin/test-znak" >"$TMP/$OPT/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$OPT/elf.header"
  timeout 15s "$TMP/$OPT/bin/test-znak" >"$TMP/$OPT/result" 2>"$TMP/$OPT/stderr"
  test ! -s "$TMP/$OPT/stderr"
  grep -Fq 'Д12-АСМ-ГАРАЗД фігур=4096 контекстів=4 перевірок=16394' "$TMP/$OPT/result"
done
cmp "$TMP/O1/result" "$TMP/O2/result"
echo 'Д12-АСМ-CI-ГАРАЗД FPC=3.2.2 O1=pass O2=pass checks=32788 pinned=yes ELF=x86-64 oracle=NOT-CHECKED energy=NOT-MEASURED'
