#!/usr/bin/env bash
# G6: справжній ELF64 із canonical .sens за абсолютним українським шляхом IDE.
# Шлях — host-механізм, не проєкція D7 і не новий SENS-закон.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for tool in fpc timeout cmp readelf grep mktemp ln git chmod; do
  command -v "$tool" >/dev/null || { echo "УКР-ШЛЯХ-БЛОК: немає $tool" >&2; exit 127; }
done
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc != 0)); then
    printf 'УКР-ШЛЯХ-ПРОВАЛ: exit=%s рядок=%s\n' "$rc" "$1" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'finish "$LINENO"' EXIT
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/фізичні форми" \
  "$TMP/звичайний каталог" "$TMP/робочий каталог ї ґ є" \
  "$TMP/корінь SENS українською"
ln -s "$ROOT/external/sens" "$TMP/корінь SENS українською/дані сенс"
UKR_ROOT="$TMP/корінь SENS українською/дані сенс"
for row in 'scripts/test-irwidefront.pas test-irwidefront' \
           'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.log" 2>&1
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/фізичні форми" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixture.log"
compile() {
  local cwd=$1 authority=$2 source=$3 target=$4 errors=$5
  (
    cd "$cwd"
    LC_ALL=C.UTF-8 timeout 25s "$TMP/bin/senswidepotikelf" \
      --скомпілювати-фізичний-потік --корінь-sens "$authority" \
      <"$source" >"$target" 2>"$errors"
  )
}
count=0
for sample in 01 09 15 16; do
  source="$TMP/фізичні форми/$sample.sens"
  expected="$TMP/фізичні форми/$sample.expected.sens"
  compile "$TMP/звичайний каталог" "$ROOT/external/sens" "$source" \
    "$TMP/$sample.base.elf" "$TMP/$sample.base.err"
  compile "$TMP/робочий каталог ї ґ є" "$UKR_ROOT" "$source" \
    "$TMP/$sample.ukr.elf" "$TMP/$sample.ukr.err"
  cmp "$TMP/$sample.base.elf" "$TMP/$sample.ukr.elf"
  readelf -h "$TMP/$sample.ukr.elf" >"$TMP/$sample.readelf.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$sample.readelf.log"
  for mode in base ukr; do
    chmod 700 "$TMP/$sample.$mode.elf"
    timeout 5s "$TMP/$sample.$mode.elf" \
      >"$TMP/$sample.$mode.actual.sens" 2>"$TMP/$sample.$mode.machine.err"
    test ! -s "$TMP/$sample.$mode.machine.err"
    cmp "$expected" "$TMP/$sample.$mode.actual.sens"
  done
  count=$((count+1))
done
test "$count" -eq 4
# Негативи повинні зупинитися ДО першого ELF-байта в stdout.
negatives=0
reject_root() {
  local authority=$1 rc=0
  compile "$TMP/робочий каталог ї ґ є" "$authority" \
    "$TMP/фізичні форми/09.sens" "$TMP/rejected.elf" "$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/rejected.elf"
  grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/rejected.err"
  negatives=$((negatives+1))
}
reject_root 'відносний/каталог сенс'
reject_root "$TMP/немає такого кореня сенс"
reject_root "$TMP/робочий каталог ї ґ є"
# Після негативів той самий бінарний код знову побайтово відтворюється.
compile "$TMP/робочий каталог ї ґ є" "$UKR_ROOT" \
  "$TMP/фізичні форми/09.sens" "$TMP/recovered.elf" "$TMP/recovered.err"
cmp "$TMP/09.base.elf" "$TMP/recovered.elf"
printf 'УКР-ШЛЯХ-ГАРАЗД фізичних=%d elf=%d виконань=%d негативів=%d повтор=тотожний pin=%s енергія=НЕ_ВИМІРЯНО\n' \
  "$count" "$((count*2))" "$((count*2))" "$negatives" "$PIN"
