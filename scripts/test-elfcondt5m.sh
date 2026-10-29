#!/usr/bin/env bash
# G6.28: реальний FPC та ELF64 x86-64, фізичний T5M stdout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -m)" == x86_64 ]] || { echo 'ПОМИЛКА: потрібна x86-64 машина' >&2; exit 78; }
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПОМИЛКА: немає Free Pascal' >&2; exit 127; }
command -v readelf >/dev/null || { echo 'ПОМИЛКА: немає readelf' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'ПОМИЛКА: немає timeout' >&2; exit 127; }
./scripts/check-pin.sh
OUT="$ROOT/build/m0.2/elfcondt5m"
mkdir -p "$OUT/units" "$OUT/witnesses"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT" \
  -otest-elfcondt5m "$ROOT/scripts/test-elfcondt5m.pas"
"$OUT/test-elfcondt5m" "$OUT/witnesses"
count=0
for elf in "$OUT"/witnesses/*.elf; do
  [[ "$elf" == *.legacy.elf ]] && continue
  stem=$(printf '%s\n' "$elf" | sed 's/\.elf$//')
  chmod +x "$elf"
  chmod +x "$stem.legacy.elf"
  readelf -h "$elf" | grep -q 'EXEC (Executable file)' ||
    { echo "ПОМИЛКА: ELF type $elf" >&2; exit 1; }
  readelf -l "$elf" | grep -q 'R E' ||
    { echo "ПОМИЛКА: RX сегмент $elf" >&2; exit 1; }
  timeout 5 "$elf" > "$stem.actual.sens"
  cmp "$stem.expected.sens" "$stem.actual.sens" ||
    { echo "ПОМИЛКА: фізичний T5M stdout $stem" >&2; exit 1; }
  timeout 5 "$stem.legacy.elf" > "$stem.actual.ascii"
  cmp "$stem.expected.ascii" "$stem.actual.ascii" ||
    { echo "ПОМИЛКА: втрачено початковий машинний результат $stem" >&2; exit 1; }
  [[ "$(stat -c%s "$stem.actual.sens")" -eq 1 ]] ||
    { echo "ПОМИЛКА: не один фізичний байт $stem" >&2; exit 1; }
  count=$((count+1))
done
[[ "$count" -eq 9 ]] || { echo 'ПОМИЛКА: не 9 реальних ELF' >&2; exit 1; }
echo "ФІЗИЧНА-МАШИННА-УМОВА-ГАРАЗД ELF=$count FPC=справжній stdout=T5M(1-байт) машинні-переходи=незмінні"
