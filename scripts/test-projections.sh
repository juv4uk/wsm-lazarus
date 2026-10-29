#!/usr/bin/env bash
# G2.27: CLI тільки над pinned G2.26 каталогом; не другий парсер.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN"
mkdir -p build/m0.2/projections/units build/m0.2/projections/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/projections/units" \
  -FE"$ROOT/build/m0.2/projections/bin" -osensproekcii \
  src/sensproekcii.lpr
BIN="$ROOT/build/m0.2/projections/bin/sensproekcii"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 15s "$BIN" external/sens 001 > "$TMP/д3"
grep -Fx 'координата: D3:001' "$TMP/д3"
grep -Fx 'ук: як-є' "$TMP/д3"
grep -Fx 'LISP: QUOTE' "$TMP/д3"
timeout 15s "$BIN" external/sens 0101001 > "$TMP/д7"
grep -Fx 'координата: D7:0101001' "$TMP/д7"
grep -Fx 'ук: ")"' "$TMP/д7"
grep -Fx 'LISP: ()' "$TMP/д7"
timeout 15s "$BIN" external/sens 0010110 > "$TMP/син"
grep -Fx 'ук: ()' "$TMP/син"
timeout 15s "$BIN" external/sens 0000000110 > "$TMP/д10"
grep -Fx 'координата: D10:0000000110' "$TMP/д10"
grep -Fx 'ук: якщо' "$TMP/д10"
grep -Fx 'en: if' "$TMP/д10"
for bits in 0012 01010x 00000000000; do
  if timeout 15s "$BIN" external/sens "$bits" > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
    echo 'ПОМИЛКА: прийнято некоректні біти або домен' >&2
    exit 1
  fi
  test ! -s "$TMP/помилка-stdout"
  grep -F 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr" >/dev/null
done
# Відсутній pinned authority directory не може надати успішний результат.
if timeout 15s "$BIN" "$TMP/немає" 001 > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
  echo 'ПОМИЛКА: відсутню таблицю допущено' >&2
  exit 1
fi
test ! -s "$TMP/помилка-stdout"
grep -F 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr" >/dev/null
# G2.30: виконати повний pinned D7 та всі 2046 точних D1–D10 ключів.
# Каталог завантажується та повністю перевіряється до першого stdout.
timeout 30s "$BIN" external/sens --домен 7 > "$TMP/д7-всі"
test "$(grep -c '^координата: D7:' "$TMP/д7-всі")" -eq 128
grep -Fx 'координата: D7:0000000' "$TMP/д7-всі"
grep -Fx 'координата: D7:1111111' "$TMP/д7-всі"
test "$(grep -c '^ук: ' "$TMP/д7-всі")" -eq 128
test "$(grep -c '^укр: ' "$TMP/д7-всі")" -eq 128
test "$(grep -c '^san: ' "$TMP/д7-всі")" -eq 128
test "$(grep -c '^en: ' "$TMP/д7-всі")" -eq 128
test "$(grep -c '^LISP: ' "$TMP/д7-всі")" -eq 128
test "$(grep -c '^sym: ' "$TMP/д7-всі")" -eq 128
timeout 60s "$BIN" external/sens --всі > "$TMP/каталог"
test "$(grep -c '^координата: D' "$TMP/каталог")" -eq 2046
test "$(grep -c '^координата: D10:' "$TMP/каталог")" -eq 1024
grep -Fx 'координата: D1:0' "$TMP/каталог"
grep -Fx 'координата: D10:1111111111' "$TMP/каталог"
# Неприпустима host-ширина не має писати навіть одну проєкцію.
for invalid in 0 07 11 D7 -1 1x; do
  if timeout 15s "$BIN" external/sens --домен "$invalid" \
      > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
    echo "ПОМИЛКА: прийнято неканонічну host-ширину $invalid" >&2
    exit 1
  fi
  test ! -s "$TMP/помилка-stdout"
  grep -Fq 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr"
done
if timeout 15s "$BIN" "$TMP/немає" --всі \
    > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
  echo 'ПОМИЛКА: відсутній authority опублікував каталог' >&2
  exit 1
fi
test ! -s "$TMP/помилка-stdout"
grep -Fq 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr"
echo 'ПРОЄКЦІЇ-КАТАЛОГ-ГАРАЗД D7=128 D10=1024 D1-D10=2046 проєкцій=6 host-негативи=так'

# G2.32 — повторно використовуємо штатний FPC T5M packer для фізичних
# реальних .sens, без нового кодування/вгадування української семантики.
mkdir -p "$ROOT/build/m0.2/projections/t5munits"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/projections/t5munits" \
  -FE"$ROOT/build/m0.2/projections/bin" -osenst5m src/senst5m.lpr
PACK="$ROOT/build/m0.2/projections/bin/senst5m"
printf '10 001 0101001 000000000001 01\n' > "$TMP/зразок.words"
timeout 15s "$PACK" --пакувати-слова "$TMP/зразок.words" > "$TMP/зразок.sens"
timeout 15s "$PACK" --перегляд "$TMP/зразок.sens" > "$TMP/круг.words"
cmp "$TMP/зразок.words" "$TMP/круг.words"
timeout 15s "$BIN" external/sens --файл "$TMP/зразок.sens" > "$TMP/фізичний"
grep -q '^СТРУКТУРА-ГАРАЗД коренів=1 ' "$TMP/фізичний"
test "$(grep -c '^слово=' "$TMP/фізичний")" -eq 5
grep -q '^слово=3 W7:0101001 трити=\[' "$TMP/фізичний"
grep -Fqx 'ук: ")"' "$TMP/фізичний"
grep -Fqx 'LISP: ()' "$TMP/фізичний"
grep -q '^слово=4 W12:000000000001 ' "$TMP/фізичний"
grep -q '^проєкції: поза D1–D10; точна ширина W12 ' "$TMP/фізичний"
test "$(grep -c '^sym: ' "$TMP/фізичний")" -eq 4
printf '10 0010110 01\n' > "$TMP/син.words"
timeout 15s "$PACK" --пакувати-слова "$TMP/син.words" > "$TMP/син.sens"
timeout 15s "$BIN" external/sens --файл "$TMP/син.sens" > "$TMP/син-фізичний"
grep -q '^слово=2 W7:0010110 ' "$TMP/син-фізичний"
test "$(grep -cx 'ук: ()' "$TMP/син-фізичний")" -eq 1
test "$(grep -cx 'укр: ()' "$TMP/син-фізичний")" -eq 1

printf '\\363' > "$TMP/зіпсований.sens"
printf '10 001\n' > "$TMP/обірваний.words"
timeout 15s "$PACK" --пакувати-слова "$TMP/обірваний.words" > "$TMP/обірваний.sens"
head -c 65537 /dev/zero > "$TMP/надмірний.sens"
cp "$TMP/зразок.sens" "$TMP/не-канон.lisp"
physical_reject() {
  local title="$1" authority="$2" path="$3"
  if timeout 20s "$BIN" "$authority" --файл "$path" \
    > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
    echo "ПОМИЛКА: прийнято фізичний негатив $title" >&2; exit 1
  fi
  test ! -s "$TMP/помилка-stdout"
  grep -Fq 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr"
}
physical_reject 'не T5M байт' external/sens "$TMP/зіпсований.sens"
physical_reject 'обірвана D2 рамка' external/sens "$TMP/обірваний.sens"
grep -Fq 'слово=3' "$TMP/помилка-stderr"
physical_reject 'межа 64KiB' external/sens "$TMP/надмірний.sens"
physical_reject 'лише фізичний .sens' external/sens "$TMP/не-канон.lisp"
physical_reject 'відсутній файл' external/sens "$TMP/немає.sens"
physical_reject 'відсутній pinned корінь' "$TMP/немає-root" "$TMP/зразок.sens"
echo 'ПРОЄКЦІЇ-ФІЗИЧНІ-ГАРАЗД T5M=побайтово D2=перед-stdout W7=SYN W12=opaque шість=так негативи=6'

echo 'ПРОЄКЦІЇ-CLI-ГАРАЗД FPC=реальний G2.26=повторно-використано D3-D7-D10=пройдено негативні=так'
