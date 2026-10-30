#!/usr/bin/env bash
# G2.54 — один наявний FPC CI gate, без нового workflow/apt.
# Шість pinned проєкцій — дані; жодного текстового semantic dispatch.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
mkdir -p "$ROOT/build"
TMP=$(mktemp -d "$ROOT/build/g2-54-proektsii-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/lib/domains"

for d in $(seq 1 10); do
  cp "external/sens/lib/domains/d${d}.lisp" "$TMP/lib/domains/d${d}.lisp"
done

timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-proektsii-atomarnist "$ROOT/scripts/test-proektsii-atomarnist.pas" \
  >"$TMP/build.log" 2>&1 || {
    tail -50 "$TMP/build.log" >&2
    exit 1
  }

run_case() {
  local mode="$1" name="$2" output
  if ! output=$(timeout 60s "$TMP/bin/test-proektsii-atomarnist" \
      "$TMP" "$mode" "$name" 2>&1); then
    printf '%s\n' "$output" >&2
    echo "ПРОЄКЦІЇ-АТОМАРНІСТЬ-ПОМИЛКА: $name" >&2
    exit 1
  fi
  printf '%s\n' "$output" | grep -Fq \
    "ПРОЄКЦІЇ-АТОМАРНІСТЬ-ГАРАЗД випадок=$name координат=2046 колонок=6 частковий=ні відновлення=так"
}

# Позитив: усі 2046 exact координат і шість проєкцій у копії pinned.
run_case добре повний-каталог

# Пізня структурна помилка після всіх 1024 допустимих D10 рядків.
printf '\n(стороння-форма)\n' >> "$TMP/lib/domains/d10.lisp"
run_case відмова зайва-D10-форма

# Неповний D10: попередні дев'ять таблиць фізично залишаються справними.
printf '(0000000000 (ук проба))\n' > "$TMP/lib/domains/d10.lisp"
run_case відмова обрізаний-D10

# Реальна файлова відмова після дев'яти вже прочитаних доменів.
rm "$TMP/lib/domains/d10.lisp"
run_case відмова відсутній-D10

# Фізична межа 1 MiB: відмова до алокації/парсингу великої D10.
truncate -s 1048577 "$TMP/lib/domains/d10.lisp"
run_case відмова завеликий-D10

# Незалежний ранній негатив D7: цілісність усіх десяти out-таблиць.
cp "external/sens/lib/domains/d10.lisp" "$TMP/lib/domains/d10.lisp"
printf '\n(стороння-форма)\n' >> "$TMP/lib/domains/d7.lisp"
run_case відмова зайва-D7-форма

echo 'VERIFIED-PROEKTSII-PASS профілів=6 позитивів=1 негативів=5 координат=2046 проєкцій=6'
