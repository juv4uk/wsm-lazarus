#!/usr/bin/env bash
# G6.72: compiler AOT RSS != ELF RSS != energy.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЕЛФ-ПАМ’ЯТЬ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for command in python3 timeout git cmp readelf; do
  command -v "$command" >/dev/null || {
    echo "ЕЛФ-ПАМ’ЯТЬ-БЛОК: відсутній $command" >&2; exit 127;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ЕЛФ-ПАМ’ЯТЬ-БЛОК: потрібен справжній Free Pascal' >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
python3 scripts/benchmark-elf-pamiat.py --самотест
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensmashyna "$ROOT/src/sensmashyna.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-senselfvykon "$ROOT/scripts/test-senselfvykon.pas"
timeout 30s "$TMP/bin/test-senselfvykon" "$TMP/fixtures"
timeout 180s python3 scripts/benchmark-elf-pamiat.py \
  --корінь "$ROOT" --свідки "$TMP/fixtures" \
  --машина "$TMP/bin/sensmashyna" --вихід "$TMP/result" --повтори 3
python3 - "$TMP/result/виміри.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as stream:
    report = json.load(stream)
assert report['енергія'] == 'ENERGY_NOT_MEASURED'
assert report['негативів'] == 5
assert report['повторів'] == 3
assert report['pinned_SENS_SHA'] == '2c498b35af53c085450eac6f51b87facf7f9aa47'
assert len(report['виміри']) == 4 * 2 * 3
assert len(report['підсумки']) == 4 * 2
assert all(x['rss_кіб'] > 0 and x['час_нс'] > 0 and x['код'] == 0
           for x in report['виміри'])
assert set(x['канал'] for x in report['виміри']) == {
    'компіляція_FPC_AOT', 'готовий_ELF64'}
PY
# Справжній негатив: змінена фізична відповідь мусить зупинити вимір
# до створення будь-якого JSON-звіту.
mkdir -p "$TMP/bad"
cp "$TMP"/fixtures/*.sens "$TMP/bad/"
printf 'пошкоджено' > "$TMP/bad/p01.expected.sens"
if timeout 60s python3 scripts/benchmark-elf-pamiat.py \
  --корінь "$ROOT" --свідки "$TMP/bad" \
  --машина "$TMP/bin/sensmashyna" --вихід "$TMP/forbidden" --повтори 3 \
  >"$TMP/neg.out" 2>"$TMP/neg.err"; then
  echo 'ЕЛФ-ПАМ’ЯТЬ-ПОМИЛКА: підмінену відповідь прийнято' >&2; exit 1
fi
test ! -e "$TMP/forbidden"
test ! -s "$TMP/neg.out"
grep -F 'Порушено точну двійкову відповідь' "$TMP/neg.err" >/dev/null
# Друга відмова: звіт не можна перезаписувати.
if timeout 20s python3 scripts/benchmark-elf-pamiat.py \
  --корінь "$ROOT" --свідки "$TMP/fixtures" \
  --машина "$TMP/bin/sensmashyna" --вихід "$TMP/result" --повтори 3 \
  >"$TMP/overwrite.out" 2>"$TMP/overwrite.err"; then
  echo 'ЕЛФ-ПАМ’ЯТЬ-ПОМИЛКА: перезапис звіту прийнято' >&2; exit 1
fi
grep -F 'Заборонено перезапис' "$TMP/overwrite.err" >/dev/null
mkdir -p "$ROOT/build/m0.2/elf-pamiat"
cp "$TMP/result/виміри.json" "$ROOT/build/m0.2/elf-pamiat/виміри.json"
echo 'ЕЛФ-ПАМ’ЯТЬ-CI-ГАРАЗД FPC=реальний ELF64=4 RSS=окремо негативи=7 енергія=НЕ_ВИМІРЯНА'
