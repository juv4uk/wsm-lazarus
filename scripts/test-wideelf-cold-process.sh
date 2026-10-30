#!/usr/bin/env bash
# G6.159 — запуск незмінних native PIE у 32 окремих процесах на кожну фізичну форму.
# Це доказ повторюваного виконання, а не вимірювання енергії чи розкиду ASLR.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for exe in timeout fpc git readelf cmp grep mktemp env tail; do
  command -v "$exe" >/dev/null || { echo "ХОЛОДНИЙ-ELF-БЛОК: немає $exe" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ХОЛОДНИЙ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 60s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
cleanup() {
  local code=$? file
  if ((code)); then
    echo "ХОЛОДНИЙ-ELF-ПРОВАЛ код=$code" >&2
    for file in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 25 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical" "$TMP/home"
FPC_BIN=${FPC:-fpc}
for row in 'scripts/test-irwidefront.pas test-irwidefront' \
           'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r src name <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.log"
if grep -Fq 'unfreed memory blocks' "$TMP/generator.err"; then
  grep -Fq '0 unfreed memory blocks' "$TMP/generator.err"
fi
physical=0
executions=0
while IFS=$'\t' read -r label kind arg_a arg_b expected width; do
  [[ -n "$label" ]]
  source="$TMP/physical/$label.sens"
  target="$TMP/$label.elf"
  expected_bytes="$TMP/physical/$label.expected.sens"
  test -s "$source"
  test -s "$expected_bytes"
  timeout 25s "$TMP/bin/senswidepotikelf" --скомпілювати-фізичний-потік \
    <"$source" >"$target" 2>"$TMP/$label.compiler.err"
  test -s "$target"
  if grep -Fq 'unfreed memory blocks' "$TMP/$label.compiler.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/$label.compiler.err"
  fi
  readelf -h "$target" >"$TMP/$label.header"
  grep -Eq 'Class:[[:space:]]+ELF64' "$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  readelf -l "$target" >"$TMP/$label.segments"
  if grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.segments"; then
    echo "ХОЛОДНИЙ-ELF-ПРОВАЛ: неочікуваний host loader ($label)" >&2
    exit 1
  fi
  chmod 700 "$target"
  for round in {1..32}; do
    if ((round % 2)); then zone=UTC; else zone=Pacific/Honolulu; fi
    # Кожен запуск — новий exec; робочий каталог не містить pinned SENS.
    (
      cd "$TMP"
      if ((round % 2)); then umask 077; else umask 022; fi
      env -i PATH=/usr/bin:/bin HOME="$TMP/home" TZ="$zone" LC_ALL=C \
        timeout 5s "$target"
    ) >"$TMP/actual.sens" 2>"$TMP/machine.err"
    test ! -s "$TMP/machine.err" || {
      cat "$TMP/machine.err" >&2; exit 1;
    }
    cmp "$expected_bytes" "$TMP/actual.sens"
    executions=$((executions+1))
  done
  physical=$((physical+1))
done <"$TMP/physical/cases.tsv"
test "$physical" -eq 16
test "$executions" -eq 512
# Після пошкодженого T5M компілятор не повинен публікувати префікс ELF.
printf '\377' >"$TMP/bad.sens"
rc=0
timeout 25s "$TMP/bin/senswidepotikelf" --скомпілювати-фізичний-потік \
  <"$TMP/bad.sens" >"$TMP/bad.elf" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/bad.elf"
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
# Відмова в попередньому процесі не впливає на повторну компіляцію.
timeout 25s "$TMP/bin/senswidepotikelf" --скомпілювати-фізичний-потік \
  <"$TMP/physical/01.sens" >"$TMP/recovered.elf" 2>"$TMP/recovered.err"
cmp "$TMP/01.elf" "$TMP/recovered.elf"
echo "ХОЛОДНИЙ-ELF-ГАРАЗД physical=$physical executions=$executions negative=1 recovery=1 oracle=NOT-CHECKED aslr=NOT-MEASURED energy=NOT-MEASURED"
# 1) Чому 512 окремих exec не доводять ні ASLR, ні енергоефективність?
# 2) Чому очікуваний результат має бути фізичним .sens, а не друком числа?
# 3) Де відбувається pinned exact-domain admission: у тесті чи у CLI?
# 4) Навіщо зміна cwd, TZ, HOME та umask між незалежними процесами?
