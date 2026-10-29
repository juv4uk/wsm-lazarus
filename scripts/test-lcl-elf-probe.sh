#!/usr/bin/env bash
# G6.34: нативний процес ELF64 + FPC та діюча кнопка GTK2/LCL.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in lazbuild fpc xvfb-run timeout readelf; do
  command -v "$tool" >/dev/null ||
    { echo "БЛОК: потрібен $tool" >&2; exit 127; }
done
[[ "$(uname -m)" == x86_64 ]] || { echo 'БЛОК: потрібен x86-64' >&2; exit 78; }
./scripts/check-pin.sh
# Не виключаємо попередні графічні/машинні докази: виконуємо їх.
bash ./scripts/test-lcl-elf-physical.sh
OUT="$ROOT/build/lcl-elf-probe"
mkdir -p "$OUT/bin" "$OUT/units"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$OUT/units" -FE"$OUT/bin" -otest-elfprobe \
  "$ROOT/scripts/test-elfprobe.pas"
W="$ROOT/build/m0.2/elfcondt5m/witnesses"
# Імена з людської укр-проєкції є лише назвами файлів.
# Незмінені байти .sens копіюємо на ASCII host-path для FPC 3.2.
A="$OUT/alias"
mkdir -p "$A"
names=(вичерпання істинна-одиниця істинний-нуль хибна-умова
       друга-гілка рівність-істина рівність-хиба
       рівність-у-тесті рівність-не-обрана)
for i in "${!names[@]}"; do
  printf -v key '%02d' "$i"
  cp "$W/${names[$i]}.sens" "$A/$key.sens"
  cp "$W/${names[$i]}.expected.sens" "$A/$key.expected.sens"
  cmp "$W/${names[$i]}.sens" "$A/$key.sens"
  cmp "$W/${names[$i]}.expected.sens" "$A/$key.expected.sens"
done
"$OUT/bin/test-elfprobe" "$A" > "$OUT/лог-elfprobe.txt"
grep -F "МАШИНА-ELF-D3-ГАРАЗД" "$OUT/лог-elfprobe.txt"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '\363' > "$TMP/зіпсований.sens"
T5M="$ROOT/build/lcl-elf-physical/bin/senst5m"
printf '0\n' > "$TMP/д1.words"
"$T5M" --pack-words "$TMP/д1.words" > "$TMP/д1.sens"
printf '10 110 10 000000000000 1 01 01\n' > "$TMP/д12.words"
"$T5M" --pack-words "$TMP/д12.words" > "$TMP/д12.sens"
BIN="$ROOT/build/lcl-elf/bin/elf-inspector"
# Той самий ізольований host каталог: перевірка no-clobber навіть
# для dangling symlink, незмінності наявних байтів та Linux ELF stdout.
ln -s "$TMP/missing-target.elf" "$TMP/dangling.elf"
LC_ALL=C.UTF-8 timeout 60 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-публікація \
  "$W/істинна-одиниця.sens" \
  "$W/істинний-нуль.sens" \
  "$W/вичерпання.sens" \
  "$W/рівність-хиба.sens" \
  "$TMP/зіпсований.sens" \
  "$TMP/д1.sens" "$TMP/д12.sens" "$TMP" \
  > "$TMP/вивід.log" 2> "$TMP/помилки.log"
test ! -s "$TMP/помилки.log"
grep -F 'LCL-ELF-ВИКОНАННЯ-ГАРАЗД' "$TMP/вивід.log"
grep -F 'LCL-ELF-ПУБЛІКАЦІЯ-ГАРАЗД GTK2=так' "$TMP/вивід.log"
grep -F 'stale=заборонено recovery=так ET_EXEC=перевірено' "$TMP/вивід.log"
test -x "$TMP/native-ok.elf"
test -x "$TMP/native-recovered.elf"
test -L "$TMP/dangling.elf" && test ! -e "$TMP/missing-target.elf"
test ! -e "$TMP/should-not-exist.elf"
test ! -e "$TMP/wrong.sens"
readelf -h "$TMP/native-ok.elf" | grep -F 'ELF64'
readelf -l "$TMP/native-ok.elf" | grep -F 'LOAD'
cmp "$TMP/native-ok.elf" "$TMP/native-recovered.elf"
timeout 5s "$TMP/native-ok.elf" > "$TMP/native-stdout.sens"
cmp "$TMP/native-stdout.sens" "$W/істинна-одиниця.expected.sens"
timeout 5s "$TMP/native-recovered.elf" > "$TMP/native-recovered-stdout.sens"
cmp "$TMP/native-recovered-stdout.sens" "$W/істинна-одиниця.expected.sens"
echo 'LCL-ELF-МАШИНА-CI-ГАРАЗД FPC=так Lazarus=GTK2/xvfb ELF=9 D12+=відхилено'
