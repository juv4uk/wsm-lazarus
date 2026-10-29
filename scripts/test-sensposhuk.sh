#!/usr/bin/env bash
# G2.42: реальний FPC з pinned шістьма проєкціями; без нового reader.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ПОШУК-ПРОЄКЦІЙ-БЛОКЕР: справжній FPC не знайдено' >&2
  exit 127
}
mkdir -p build/m0.2/poshuk/units build/m0.2/poshuk/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/poshuk/units" \
  -FE"$ROOT/build/m0.2/poshuk/bin" -osensposhuk src/sensposhuk.lpr
BIN="$ROOT/build/m0.2/poshuk/bin/sensposhuk"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Шість різних людських проєкцій тієї самої фізичної координати.
surfaces=(ук укр san en LISP sym)
spellings=('як-є' 'як-є' 'svarūpa' 'quote' 'QUOTE' "\"'\"")
for i in "${!surfaces[@]}"; do
  timeout 20s "$BIN" external/sens "${surfaces[$i]}" "${spellings[$i]}" D3 > "$TMP/дійсний"
  printf 'координата: D3:001\nзбігів=1 викличність=не-перевірено\n' > "$TMP/очікуваний"
  diff -u "$TMP/очікуваний" "$TMP/дійсний"
done

# D3:001 та D7:0100111 мають ОДНАКОВУ sym-проєкцію "'".
# Заборонено мовчки обрати одну координату або вважати D7 викличною.
timeout 20s "$BIN" external/sens sym "\"'\"" > "$TMP/дійсний"
printf 'координата: D3:001\nкоордината: D7:0100111\nзбігів=2 викличність=не-перевірено\n' > "$TMP/очікуваний"
diff -u "$TMP/очікуваний" "$TMP/дійсний"
timeout 20s "$BIN" external/sens sym "\"'\"" D7 > "$TMP/дійсний"
printf 'координата: D7:0100111\nзбігів=1 викличність=не-перевірено\n' > "$TMP/очікуваний"
diff -u "$TMP/очікуваний" "$TMP/дійсний"

# Бітова ширина та провідні нулі D7 збережені, quoted ')' — ТЕКСТ.
timeout 20s "$BIN" external/sens укр '")"' D7 > "$TMP/дійсний"
printf 'координата: D7:0101001\nзбігів=1 викличність=не-перевірено\n' > "$TMP/очікуваний"
diff -u "$TMP/очікуваний" "$TMP/дійсний"

reject() {
  local name="$1"; shift
  local rc=0
  timeout 20s "$BIN" "$@" > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr" || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "ПОШУК-ПРОЄКЦІЙ-ТЕСТ-ПОМИЛКА: $name код=$rc, очікувано 2" >&2
    exit 1
  fi
  test ! -s "$TMP/помилка-stdout" || {
    echo "ПОШУК-ПРОЄКЦІЙ-ТЕСТ-ПОМИЛКА: частковий stdout: $name" >&2
    exit 1
  }
  grep -Fq 'ПОШУК-ПРОЄКЦІЙ-ПОМИЛКА:' "$TMP/помилка-stderr"
}
reject 'неправильний D12' external/sens ук 'як-є' D12
reject 'неправильний D0' external/sens ук 'як-є' D0
reject 'неканонічний D03' external/sens ук 'як-є' D03
reject 'неприпустимий D11' external/sens ук 'як-є' D11
reject 'неприпустиме d3' external/sens ук 'як-є' d3
reject 'невідомий suface' external/sens sa svarūpa D3
reject 'порожня проєкція' external/sens ук '()' D7
reject 'порожній аргумент' external/sens ук '' D3
reject 'без збігів' external/sens ук 'немає-такої-проєкції' D3
reject 'D7 SYN не має ук-тексту' external/sens ук SYN D7
reject 'немає pinned авторитету' "$TMP/немає" ук 'як-є' D3
# G2.44: новий opt-in перетин перевіряє ОБИДВІ pinned поверхні
# одного exact Dn:bits рядка. Колізія D3/D7 не є семантичним alias.
pair_expect() {
  local expected="$1"; shift
  timeout 20s "$BIN" external/sens --перетин "$@" > "$TMP/дійсний"
  printf '%s\n' "$expected" 'збігів=1 викличність=не-перевірено' > "$TMP/очікуваний"
  diff -u "$TMP/очікуваний" "$TMP/дійсний"
}
pair_expect 'координата: D3:001' sym "\"'\"" укр як-є
pair_expect 'координата: D7:0100111' sym "\"'\"" укр "\"'\"" D7
pair_expect 'координата: D3:001' ук як-є san svarūpa D3
pair_expect 'координата: D3:001' en quote LISP QUOTE D3
pair_expect 'координата: D3:001' укр як-є укр як-є D3
pair_expect 'координата: D7:0101001' укр '")"' san '")"' D7

# Однакові символьні тексти в обох колонках не усувають неоднозначність.
timeout 20s "$BIN" external/sens --перетин sym "\"'\"" sym "\"'\"" > "$TMP/дійсний"
printf 'координата: D3:001\nкоордината: D7:0100111\nзбігів=2 викличність=не-перевірено\n' > "$TMP/очікуваний"
diff -u "$TMP/очікуваний" "$TMP/дійсний"

# Нова механіка не може публікувати часткові рядки після пізньої
# суперечності двох людських проєкцій або поганого authority.
reject 'дві суперечливі проєкції' external/sens --перетин sym "\"'\"" укр 'порожній?' 
reject 'пізня суперечність D7' external/sens --перетин sym "\"'\"" укр як-є D7
reject 'немає спільного D7 SYN написання' external/sens --перетин ук SYN en SYN D7
reject 'порожній другий напис' external/sens --перетин sym "\"'\"" укр ''
reject 'порожня перша проєкція' external/sens --перетин sym '()' укр як-є
reject 'неправильна друга колонка' external/sens --перетин sym "\"'\"" sa svarūpa
reject 'D12+ не D7' external/sens --перетин sym "\"'\"" укр як-є D12
reject 'неканонічний фільтр' external/sens --перетин sym "\"'\"" укр як-є D03
reject 'неповна пара' external/sens --перетин sym "\"'\"" укр
reject 'зайва пара' external/sens --перетин sym "\"'\"" укр як-є D3 зайве
reject 'недоступний pinned' "$TMP/немає" --перетин sym "\"'\"" укр як-є
echo 'ПЕРЕТИН-ПРОЄКЦІЙ-ГАРАЗД FPC=реальний пари=7 міждоменно=2 D7=дані негативи=11'

echo 'ПОШУК-ПРОЄКЦІЙ-ГАРАЗД FPC=реальний проєкцій=6 колізія=D3+D7 D12+=закрито негативи=11'
