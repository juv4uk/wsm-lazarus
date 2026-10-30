#!/usr/bin/env bash
# G6 — той самий pinned compiler з cwd Lazarus IDE, без нового SENS закону.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "КОМПІЛЯТОР-КАТАЛОГ-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
for tool in fpc git timeout cmp grep readelf mktemp; do
  command -v "$tool" >/dev/null || {
    echo "КОМПІЛЯТОР-КАТАЛОГ-БЛОК: немає $tool" >&2; exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
finish() {
  local rc=$? file
  if ((rc)); then
    echo "КОМПІЛЯТОР-КАТАЛОГ-ПРОВАЛ: код=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 22 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/foreign" "$TMP/empty-root"
for spec in "scripts/test-irwidefront.pas test-irwidefront" \
            "src/senswidefrontelf.lpr senswidefrontelf"; do
  read -r source executable <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build.log" 2>&1 || {
      cat "$TMP/$executable.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$executable"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generate.log" 2>"$TMP/generate.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generate.log"
heap_ok() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1"
  fi
}
heap_ok "$TMP/generate.err"
MODE=--скомпілювати-фізичну-форму
VERIFY=--звірити-походження
ROOT_OPTION=--корінь-sens
COUNT=0
for label in 01 09 16; do
  source="$TMP/physical/$label.sens"
  expected="$TMP/physical/$label.expected.sens"
  test -s "$source" && test -s "$expected"
  timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" "$source" \
    "$TMP/$label.elf" >"$TMP/old-$label.log" 2>"$TMP/old-$label.err"
  heap_ok "$TMP/old-$label.err"
  (
    cd "$TMP/foreign"
    timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" "$source" \
      "$TMP/foreign/$label.elf" "$ROOT_OPTION" "$ROOT/external/sens"
  ) >"$TMP/new-$label.log" 2>"$TMP/new-$label.err"
  heap_ok "$TMP/new-$label.err"
  test -x "$TMP/foreign/$label.elf"
  cmp "$TMP/$label.elf" "$TMP/foreign/$label.elf"
  timeout 10s readelf -h "$TMP/foreign/$label.elf" >"$TMP/$label.header.log"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header.log"
  (
    cd "$TMP/foreign"
    timeout 25s "$TMP/bin/senswidefrontelf" "$VERIFY" "$source" \
      "$TMP/foreign/$label.elf" "$ROOT_OPTION" "$ROOT/external/sens"
  ) >"$TMP/verify-$label.log" 2>"$TMP/verify-$label.err"
  grep -Fq 'ЕЛЬФ-ПОХОДЖЕННЯ-ГАРАЗД:' "$TMP/verify-$label.log"
  heap_ok "$TMP/verify-$label.err"
  timeout 5s "$TMP/foreign/$label.elf" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$expected" "$TMP/$label.actual.sens"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 3

# Негативи запускаємо ЗА МЕЖАМИ cwd репозиторію.
# Жоден не має змінювати готовий ELF чи створювати частковий stdout.
cp "$TMP/foreign/01.elf" "$TMP/original.elf"
NEG=0
reject() {
  local name="$1"
  shift
  local rc=0
  (
    cd "$TMP/foreign"
    timeout 25s "$TMP/bin/senswidefrontelf" "$@"
  ) >"$TMP/reject-$name.out" 2>"$TMP/reject-$name.err" || rc=$?
  if ((rc != 2)); then
    echo "КОМПІЛЯТОР-КАТАЛОГ: неправильна відмова $name rc=$rc" >&2
    return 1
  fi
  test ! -s "$TMP/reject-$name.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/reject-$name.err"
  heap_ok "$TMP/reject-$name.err"
  cmp "$TMP/original.elf" "$TMP/foreign/01.elf"
  NEG=$((NEG+1))
}
reject відносний "$MODE" "$TMP/physical/01.sens" "$TMP/foreign/01.elf" \
  "$ROOT_OPTION" external/sens
reject відсутній "$MODE" "$TMP/physical/01.sens" "$TMP/foreign/01.elf" \
  "$ROOT_OPTION" "$TMP/missing"
reject без-контракту "$VERIFY" "$TMP/physical/01.sens" "$TMP/foreign/01.elf" \
  "$ROOT_OPTION" "$TMP/empty-root"
reject прапорець "$MODE" "$TMP/physical/01.sens" "$TMP/foreign/01.elf" \
  --чужий-корінь "$ROOT/external/sens"
reject порожній "$MODE" "$TMP/physical/01.sens" "$TMP/foreign/01.elf" \
  "$ROOT_OPTION" ''
# Старий 3-аргументний CLI з чужого cwd не стає непомітно іншим authority.
reject старий-cwd "$VERIFY" "$TMP/physical/01.sens" "$TMP/foreign/01.elf"
test "$NEG" -eq 6
# Після негативів повторна компіляція з явним коренем не змінює ELF.
(
  cd "$TMP/foreign"
  timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" "$TMP/physical/01.sens" \
    "$TMP/foreign/recovered.elf" "$ROOT_OPTION" "$ROOT/external/sens"
) >"$TMP/recovered.log" 2>"$TMP/recovered.err"
heap_ok "$TMP/recovered.err"
cmp "$TMP/original.elf" "$TMP/foreign/recovered.elf"
echo "КОМПІЛЯТОР-КАТАЛОГ-ГАРАЗД fpc=checked physical=$COUNT elf=$COUNT executable=$COUNT provenance=$COUNT negative=$NEG legacy=так recovered=так oracle=NOT-CHECKED energy=NOT-MEASURED"
# Типи: аргументи шляху — host String, джерело/результат — фізичні байти.
# Атомарність: PublishNewELF64 не відкриває ціль до повного pinned admission.
# Питання: 1) Чому cwd не може визначати мовний закон?
# 2) Чому перевірка походження сильніша за заголовок ELF?
# 3) Чим відрізняються D7 проєкція та шлях host файлової системи?
# 4) Чому тест не заявляє незалежний семантичний oracle?
