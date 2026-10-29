#!/usr/bin/env bash
# G6.152: різні FPC-складання й host-середовища не змінюють exact ELF64.
# Канонічні дані .sens — тільки packed T5M; цей тест не визначає SENS-законів.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc != 0)); then
    printf 'WIDEIR-ВІДТВОРЮВАНІСТЬ-ПРОВАЛ: рядок=%s код=%s\n' "$1" "$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'finish "$LINENO"' EXIT
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout cmp grep readelf stat mktemp tail wc ln cp; do
  command -v "$exe" >/dev/null || { echo "Немає $exe" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
mkdir -p "$TMP/generator/bin" "$TMP/generator/units" "$TMP/physical"
# Генератор бере точні фізичні форми/очікувані T5M із чинного pinned gate.
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/generator/units" -FE"$TMP/generator/bin" \
  -otest-irwidefront "$ROOT/scripts/test-irwidefront.pas" \
  >"$TMP/generator-build.log" 2>&1
timeout 45s "$TMP/generator/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.log"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 16
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Fq '0 unfreed memory blocks' "$1"
  fi
}
check_heap "$TMP/generator.err"
# Не вбудовуємо в Pascal ані D5/D6 законів, ані текстового dispatch.
for mode in a b; do
  mkdir -p "$TMP/$mode/bin" "$TMP/$mode/units" \
    "$TMP/$mode/work/external" "$TMP/$mode/home"
  ln -s "$ROOT/external/sens" "$TMP/$mode/work/external/sens"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$mode/units" -FE"$TMP/$mode/bin" \
    -osenswidezakhystzahalelf "$ROOT/src/senswidezakhystzahalelf.lpr" \
    >"$TMP/$mode-build.log" 2>&1
  test -x "$TMP/$mode/bin/senswidezakhystzahalelf"
done
count=0
while IFS=$'\t' read -r label kind a b expected width; do
  test -n "$label"
  for mode in a b; do
    cp "$TMP/physical/$label.sens" "$TMP/$mode/work/$label.sens"
    if [[ $mode == a ]]; then
      (
        cd "$TMP/$mode/work"; umask 077
        env TZ=UTC LC_ALL=C HOME="$TMP/$mode/home" SOURCE_DATE_EPOCH=0 \
          timeout 25s "$TMP/$mode/bin/senswidezakhystzahalelf" \
          --скомпілювати-захищену-форму "$label.sens" "$label.elf"
      ) >"$TMP/$mode-$label.log" 2>"$TMP/$mode-$label.err"
    else
      (
        cd "$TMP/$mode/work"; umask 022
        env TZ=Pacific/Honolulu LC_ALL=C.UTF-8 HOME="$TMP/$mode/home" \
          SOURCE_DATE_EPOCH=1234567890 \
          timeout 25s "$TMP/$mode/bin/senswidezakhystzahalelf" \
          --скомпілювати-захищену-форму "$label.sens" "$label.elf"
      ) >"$TMP/$mode-$label.log" 2>"$TMP/$mode-$label.err"
    fi
    grep -Fq 'write=checked' "$TMP/$mode-$label.log"
    check_heap "$TMP/$mode-$label.err"
    test -x "$TMP/$mode/work/$label.elf"
    test "$(stat -c '%a' "$TMP/$mode/work/$label.elf")" = 700
    readelf -h "$TMP/$mode/work/$label.elf" >"$TMP/$mode-$label-header.log"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$mode-$label-header.log"
    readelf -l "$TMP/$mode/work/$label.elf" >"$TMP/$mode-$label-segments.log"
    ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$mode-$label-segments.log"
    timeout 5s "$TMP/$mode/work/$label.elf" >"$TMP/$mode-$label.actual.sens" \
      2>"$TMP/$mode-$label-machine.err"
    test ! -s "$TMP/$mode-$label-machine.err"
    cmp "$TMP/physical/$label.expected.sens" "$TMP/$mode-$label.actual.sens"
  done
  cmp "$TMP/a/work/$label.sens" "$TMP/b/work/$label.sens"
  cmp "$TMP/a/work/$label.elf" "$TMP/b/work/$label.elf"
  cmp "$TMP/a-$label.actual.sens" "$TMP/b-$label.actual.sens"
  count=$((count+1))
done < "$TMP/physical/cases.tsv"
test "$count" -eq 16
# Ті самі два binary CLI після пошкоджених байтів повинні відмовити
# без створення ELF, а наступна правильна форма — знову виконатися.
for mode in a b; do
  cp "$TMP/physical/bad-t5m.sens" "$TMP/$mode/work/bad.sens"
  rc=0
  (cd "$TMP/$mode/work" && timeout 20s "$TMP/$mode/bin/senswidezakhystzahalelf" \
    --скомпілювати-захищену-форму bad.sens bad.elf) \
    >"$TMP/$mode-bad.log" 2>"$TMP/$mode-bad.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$mode-bad.log"
  test ! -e "$TMP/$mode/work/bad.elf" && test ! -L "$TMP/$mode/work/bad.elf"
  grep -Fq 'ВІДМОВА:' "$TMP/$mode-bad.err"
  (cd "$TMP/$mode/work" && timeout 20s "$TMP/$mode/bin/senswidezakhystzahalelf" \
    --скомпілювати-захищену-форму 01.sens recovered.elf) \
    >"$TMP/$mode-recovered.log" 2>"$TMP/$mode-recovered.err"
  cmp "$TMP/$mode/work/01.elf" "$TMP/$mode/work/recovered.elf"
done
printf 'WIDEIR-ВІДТВОРЮВАНІСТЬ-ГАРАЗД profiles=4 inputs=%d fpc_builds=2 elf=32 executions=32 identical=16 negative=2 recovery=2 energy=NOT-MEASURED\n' "$count"
# Типи: label — лише host індекс; source/result — exact physical T5M;
# ELF — host image. Тимчасові файли належать trap і видаляються по EXIT.
# Питання: 1) Чому cmp ELF сильніший за збіг результатів?
# 2) Чому D24 не можна виводити з довжини packed файла?
# 3) Для чого зміна cwd/TZ/umask, якщо pinned SENS той самий?
# 4) Чому відмова не має створювати partial ELF?
# 5) Чому цей тест не є вимірюванням енергоефективності?
