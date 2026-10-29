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
echo 'ПОШУК-ПРОЄКЦІЙ-ГАРАЗД FPC=реальний проєкцій=6 колізія=D3+D7 D12+=закрито негативи=11'
