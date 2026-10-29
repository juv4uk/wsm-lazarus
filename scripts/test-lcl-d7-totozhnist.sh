#!/usr/bin/env bash
# G3.32 — справжні LCL кліки виконують D3:101 над точно цитованими D7.
# Незалежний pinned SENS запускається на ТИХ САМИХ двійкових файлах.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in lazbuild xvfb-run fpc timeout cmp git; do
  command -v "$tool" >/dev/null || {
    echo "Д7-ТОТОЖНІСТЬ-LCL-БЛОК: бракує $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '0010110' external/sens/lib/domains/d7.lisp
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(eq-operands . admitted-atoms-only)'
# Позитивні та негативні регресії чинного фізичного D3:101 не відключаємо.
timeout 240s bash ./scripts/test-native-eq.sh > /dev/null
timeout 240s bash ./scripts/test-t5m-cli.sh > /dev/null

ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'Д7-ТОТОЖНІСТЬ-LCL-БЛОК: немає незалежного SENS oracle' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'Д7-ТОТОЖНІСТЬ-LCL-БЛОК: невірний pin незалежного oracle' >&2; exit 1;
}

mkdir -p build/lcl-d7-totozhnist/bin build/lcl-d7-totozhnist/units
timeout 180s lazbuild --widgetset=gtk2 --build-all gui/sens-d7-totozhnist.lpi
BIN="$ROOT/build/lcl-d7-totozhnist/bin/sens-d7-totozhnist"
PACK="$ROOT/build/m0.2/bin/senst5m"
test -x "$BIN" && test -x "$PACK"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '10 101 10 001 0010110 01 10 001 0010110 01 01' > "$TMP/однакові.words"
printf '%s\n' '10 101 10 001 0010110 01 10 001 0000000 01 01' > "$TMP/різні.words"
"$PACK" --пакувати-слова "$TMP/однакові.words" > "$TMP/однакові.sens"
"$PACK" --пакувати-слова "$TMP/різні.words" > "$TMP/різні.sens"
# G3.34: зовнішні файли фізично створює вже перевірений FPC senst5m,
# не сам графічний редактор і не текстовий розбір української проєкції.
printf '%s\n' '10 101 1 10 001 0000001 01 01' > "$TMP/мішані.words"
printf '%s\n' '10 001 0010110 01' > "$TMP/інша-голова.words"
printf '%s\n' '10 101 10 001 000000000000 01 1 01' > "$TMP/ширина.words"
printf '%s\n' '10 101 1 1 01 1' > "$TMP/два-корені.words"
printf '%s\n' '10 101 0010110 10 001 0010110 01 01' > "$TMP/голий-д7.words"
for name in мішані інша-голова ширина два-корені голий-д7; do
  "$PACK" --пакувати-слова "$TMP/$name.words" > "$TMP/$name.sens"
done
cat "$TMP/однакові.sens" > "$TMP/зіпсовано.sens"
printf '\363' >> "$TMP/зіпсовано.sens"
printf '%s\n' '(сполучити ні так)' > "$TMP/текст.lisp"
test -s "$TMP/однакові.sens" && test -s "$TMP/різні.sens" &&
  test -s "$TMP/мішані.sens"
"$PACK" --перевірити-структуру "$TMP/однакові.sens" > "$TMP/структура"
grep -Fq 'коренів=1 ' "$TMP/структура"

# Самотест справжнього вікна з натисканням кнопки, не окремий parser/mock.
LC_ALL=C.UTF-8 timeout 100s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$BIN" --самоперевірка "$TMP/однакові.sens" "$TMP/різні.sens" \
    "$TMP/мішані.sens" "$TMP/зіпсовано.sens" "$TMP/інша-голова.sens" \
    "$TMP/ширина.sens" "$TMP/текст.lisp" "$TMP/два-корені.sens" \
    "$TMP/голий-д7.sens" \
  >"$TMP/lcl.stdout" 2>"$TMP/lcl.stderr" || {
    cat "$TMP/lcl.stdout" "$TMP/lcl.stderr" >&2;exit 1;
  }
test ! -s "$TMP/lcl.stderr"
grep -Fq 'LCL-Д3-Д7-ТОТОЖНІСТЬ-ГАРАЗД' "$TMP/lcl.stdout"
grep -Fq 'шість-проєкцій=pinned' "$TMP/lcl.stdout"
grep -Fq 'LCL-Д7-ІМПОРТ-ГАРАЗД реальний-файл=так' "$TMP/lcl.stdout"
grep -Fq 'негативи=шість recovery=так' "$TMP/lcl.stdout"

# Ті самі фізичні байти незалежно виконує pinned Rust/Zig SENS.
printf '1\n' > "$TMP/однакові.expected"
printf '0\n' > "$TMP/різні.expected"
printf '0\n' > "$TMP/мішані.expected"
for case_name in однакові різні мішані; do
  timeout 60s "$ORACLE" "$TMP/$case_name.sens" \
    > "$TMP/$case_name.oracle" 2>"$TMP/$case_name.oracle.err" || {
      echo "Д7-LCL-ОРАКУЛ-ПОМИЛКА: $case_name" >&2
      cat "$TMP/$case_name.oracle.err" >&2;exit 1;
    }
  test ! -s "$TMP/$case_name.oracle.err"
  if ! cmp -s "$TMP/$case_name.expected" "$TMP/$case_name.oracle"; then
    echo "Д7-LCL-ОРАКУЛ-РОЗБІЖНІСТЬ: $case_name" >&2
    diff -u "$TMP/$case_name.expected" "$TMP/$case_name.oracle" >&2 || true
    exit 1
  fi
done
echo "Д7-ТОТОЖНІСТЬ-LCL-ОРАКУЛ-ГАРАЗД pinned=$PIN FPC=так Lazarus=GTK2 Xvfb=так ті-самі-байти=3 зовнішній-файл=так D7-SYN=дані D12+=відхилено"
