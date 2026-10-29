#!/usr/bin/env bash
# G3.43 — реальна фізична арифметика в Lazarus через чинний runtime.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for bin in fpc lazbuild xvfb-run timeout python3; do
  command -v "$bin" >/dev/null || { echo "LCL-СУМА-БЛОК: немає $bin" >&2; exit 127; }
done
./scripts/check-pin.sh
# НІ ОДНОГО наявного арифметичного тесту не послаблено.
timeout 240s bash scripts/test-numericadd.sh
mkdir -p build/lcl-suma-ogliad/bin build/lcl-suma-ogliad/units
timeout 180s lazbuild --widgetset=gtk2 --build-all gui/sens-suma-ogliad.lpi
BIN="$ROOT/build/lcl-suma-ogliad/bin/sens-suma-ogliad"
NUM="$ROOT/build/m0.2/bin/senschyslo"
PACK="$ROOT/build/m0.2/bin/senst5m"
test -x "$BIN" && test -x "$NUM"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_num () {
  local id="$1" domain="$2" decimal="$3"
  printf '%s\n' "$decimal" > "$TMP/$id.lisp"
  "$NUM" --з-укр "$domain" "$TMP/$id.lisp" "$TMP/$id.sens"
  test -s "$TMP/$id.sens"
}
make_num p7 D12 7
make_num n7 D12 -7
make_num pmax12 D12 2047
make_num p1 D12 1
make_num nmin24 D24 -8388608
make_num n1_24 D24 -1
make_num p1_48 D48 1
make_num p2_48 D48 2
make_num p1_96 D96 1
make_num p2_96 D96 2
make_num p1_192 D192 1
make_num p2_192 D192 2
# 2^191-1 — максимальне додатне signed D192, не округляти до Int64.
python3 - "$TMP/max192.words" <<'PY'
import sys
with open(sys.argv[1], 'w', encoding='ascii') as output:
    output.write('0' + '1' * 191 + '\n')
PY
if [[ ! -x "$PACK" ]]; then
  fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/numericadd-units" \
    -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
fi
"$PACK" --пакувати-слова "$TMP/max192.words" > "$TMP/max192.sens"
printf '\363' > "$TMP/bad.sens"
printf '%s\n' '(додати 7 -7)' > "$TMP/human.lisp"
test ! -e "$TMP/missing.sens"
if ! timeout 50s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$BIN" --самоперевірка \
  "$TMP/p7.sens" "$TMP/n7.sens" "$TMP/pmax12.sens" "$TMP/p1.sens" \
  "$TMP/nmin24.sens" "$TMP/n1_24.sens" \
  "$TMP/p1_48.sens" "$TMP/p2_48.sens" \
  "$TMP/p1_96.sens" "$TMP/p2_96.sens" \
  "$TMP/p1_192.sens" "$TMP/p2_192.sens" "$TMP/max192.sens" \
  "$TMP/bad.sens" "$TMP/human.lisp" "$TMP/missing.sens" \
  > "$TMP/gui.out" 2> "$TMP/gui.err"; then
  cat "$TMP/gui.out" >&2
  cat "$TMP/gui.err" >&2
  echo 'LCL-СУМА-ПРОВАЛ: GTK2 кнопка/фізичний runtime не пройшли' >&2
  exit 1
fi
test ! -s "$TMP/gui.err"
grep -Fq 'LCL-СУМА-ГАРАЗД' "$TMP/gui.out"
grep -Fq 'output=T5M-byte-exact' "$TMP/gui.out"
# Незалежний наявний фізичний CLI на тих самих файлах має ТІ САМІ байти.
"$ROOT/build/m0.2/bin/senschyslododaty" D12 \
   "$TMP/pmax12.sens" "$TMP/p1.sens" > "$TMP/from-cli.sens" \
   2> "$TMP/cli.err"
printf '2048\n' > "$TMP/want.lisp"
"$NUM" --з-укр D24 "$TMP/want.lisp" "$TMP/want.sens"
cmp "$TMP/want.sens" "$TMP/from-cli.sens"
echo 'LCL-СУМА-ЗБІРКА-ГАРАЗД FPC=checked Lazarus=GTK2/Xvfb D12-D192=реальне-додавання'
