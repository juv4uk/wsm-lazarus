#!/usr/bin/env bash
# GЕ.5: збирання справжнього FPC→ELF; незалежний pinned SENS oracle.
# CI не має права публікувати синтетичні чи недоступні RAPL джоулі.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'КОМПІЛЬОВАНА-ЕНЕРГІЯ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for cmd in fpc python3 timeout git; do
  command -v "$cmd" >/dev/null || {
    echo "КОМПІЛЬОВАНА-ЕНЕРГІЯ-БЛОК: немає $cmd" >&2
    exit 127
  }
done
test "$(git -C sens-oracle rev-parse HEAD)" = \
  1f1bf676eeac605e065035d9dd2adaae807f1788
test -x "$ROOT/sens-oracle/target/release/sens"

python3 scripts/energy/compiled-elf.py --самотест

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"

# Кожна одиниця збирається реальним FPC, без підміни генератора скриптом.
for spec in \
  'src/sensmashyna.lpr sensmashyna' \
  'src/sensvykon.lpr sensvykon' \
  'src/senst5m.lpr senst5m' \
  'scripts/energy/sensrapl.lpr sensrapl' \
  'scripts/test-sensmashyna.pas test-sensmashyna'; do
  read -r path target <<< "$spec"
  timeout 180s fpc -B -O2 -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
    "-o$target" "$ROOT/$path"
  test -x "$TMP/bin/$target"
done
timeout 60s "$TMP/bin/test-sensmashyna" "$ROOT/external/sens" "$TMP/свідки"

ARGS=(
  --корінь "$ROOT"
  --свідки "$TMP/свідки"
  --машина "$TMP/bin/sensmashyna"
  --виконавець "$TMP/bin/sensvykon"
  --читач "$TMP/bin/senst5m"
  --оракул "$ROOT/sens-oracle/target/release/sens"
)

# Позитив: кожен compiled ELF реально виконується до перевіреного T5M,
# FPC та незалежний SENS CLI теж повертають допущені відповіді.
timeout 180s python3 scripts/energy/compiled-elf.py "\${ARGS[@]}"

# Preflight читає усі 4 позитиви перед виміром. Негативи не можуть
# створити звіт із вигаданими або частковими фізичними джоулями.
status=0
timeout 180s python3 scripts/energy/compiled-elf.py "\${ARGS[@]}" \
  --вимір --живлення "$TMP/немає-рапл" --rapl "$TMP/bin/sensrapl" \
  --вихід "$TMP/невиміряно.json" >"$TMP/без-рапл.out" \
  2>"$TMP/без-рапл.err" || status=$?
test "$status" -eq 2
test ! -e "$TMP/невиміряно.json"
grep -Fq 'ENERGY_NOT_MEASURED' "$TMP/без-рапл.err"

# Незалежний byte-exact негатив: допуск фізичного результату НЕ
# зводиться до текстової відповіді і не приймає змінені очікувані байти.
cp "$TMP/свідки/тотожні-00.expected.sens" "$TMP/правильний.sens"
: > "$TMP/свідки/тотожні-00.expected.sens"
status=0
timeout 180s python3 scripts/energy/compiled-elf.py "\${ARGS[@]}" \
  >"$TMP/помилкова-відповідь.out" 2>"$TMP/помилкова-відповідь.err" || status=$?
test "$status" -eq 2
grep -Fq 'ЕЛФ-ЕНЕРГІЯ-БЛОК:' "$TMP/помилкова-відповідь.err"
cp "$TMP/правильний.sens" "$TMP/свідки/тотожні-00.expected.sens"

# Чинний строгий нативний RAPL gate без фізичного вимірювання в CI.
timeout 180s bash scripts/energy/test-sensrapl.sh
echo 'КОМПІЛЬОВАНА-ЕНЕРГІЯ-ГАРАЗД FPC=5 ELF=4 pinned-оракул=4 RAPL=самотест+негатив joules=НЕ-ВИМІРЯНО'
