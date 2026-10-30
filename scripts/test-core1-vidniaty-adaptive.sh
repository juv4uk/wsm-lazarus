#!/usr/bin/env bash
# G6.177 — оригінальний фізичний Core1 SUB у перевіреному ELF64 D12/D24.
# Ніякої нової семантики: upstream pinned SENS REPL є незалежним oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЯДРО1-ВІДНЯТИ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in git fpc timeout cmp readelf objdump grep sha256sum mktemp wc python3; do
  command -v "$t" >/dev/null || { echo "ЯДРО1-ВІДНЯТИ-БЛОК: немає $t" >&2;exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 60s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test -s external/sens/lib/core1.sens
grep -Fq '(визначити ядро1-відняти' external/sens/lib/core1.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]];then
  echo 'ЯДРО1-ВІДНЯТИ-БЛОК: незалежний pinned SENS oracle обов’язковий' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$? file
  if ((rc));then
    echo "ЯДРО1-ВІДНЯТИ-ПРОВАЛ rc=$rc" >&2
    for file in "$TMP"/*.err "$TMP"/*.out "$TMP"/*.build; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2;tail -n 50 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'echo "ЯДРО1-ВІДНЯТИ-ЗУПИНКА line=$LINENO command=$BASH_COMMAND" >&2' ERR
mkdir -p "$TMP/bin" "$TMP/unit-core1" "$TMP/unit-adapt" \
  "$TMP/unit-fixtures" "$TMP/data"
for row in \
  'src/senscore1vidniatyadaptive.lpr senscore1vidniatyadaptive unit-core1' \
  'src/sensd12addpotikadaptive.lpr sensd12addpotikadaptive unit-adapt' \
  'scripts/test-core1potik-fixtures.pas test-core1potik-fixtures unit-fixtures';do
  read -r src exe unit <<< "$row"
  timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$unit" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$src" >"$TMP/$exe.build" 2>&1 || {
       cat "$TMP/$exe.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$exe"
done
timeout 35s "$TMP/bin/test-core1potik-fixtures" "$TMP/data" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
test ! -s "$TMP/fixtures.err"
grep -Fq 'CORE1-POTIK-FIXTURES-OK total=40 d12=33 d24=7 bad=7' \
 "$TMP/fixtures.out"
MODE=--ядро1-адаптивне-віднімання
ELF="$TMP/ядро1-відняти-адаптивне.elf"
timeout 90s "$TMP/bin/senscore1vidniatyadaptive" "$MODE" "$ELF" \
  >"$TMP/compile.out" 2>"$TMP/compile.err"
test -x "$ELF"
grep -Fq 'stdout=T5M-D12-or-D24' "$TMP/compile.out"
# Незалежне повторне компонування із фізичного pinned D5 якоря
# повинно видати абсолютно однаковий ELF, а не схожий текстовий результат.
timeout 60s "$TMP/bin/sensd12addpotikadaptive" \
  --зібрати-адаптивне-D5-віднімання "$TMP/data/s00.sens" "$TMP/donor.elf" \
  >"$TMP/donor.out" 2>"$TMP/donor.err"
test ! -s "$TMP/donor.err"
cmp "$ELF" "$TMP/donor.elf"
timeout 8s readelf -h "$ELF" >"$TMP/header"
timeout 8s readelf -l "$ELF" >"$TMP/segments"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments"
# Адаптивний runtime додає code island ПІСЛЯ таблиць донора.
# Перші 900 байтів не містять цей блок — такий тест дає хибний RED.
# Виявляємо у повному ELF точний machine signature, перевіряємо його
# унікальність і дизасемблюємо ЛИШЕ справжній острів інструкцій.
python3 - "$ELF" "$TMP/machine" <<'PY'
from pathlib import Path
import sys
image = Path(sys.argv[1]).read_bytes()
signature = bytes.fromhex('44 89 c0 44 29 c8 89 c3')
found = image.find(signature, 120)
assert image[:4] == b'\x7fELF', 'ELF64 заголовок відсутній'
assert found >= 120, 'немає машинного SUB у фізичному ELF'
assert image.find(signature, found + 1) == -1, 'неоднозначний SUB code island'
assert len(image) >= found + 48, 'машинний code island обрізано'
Path(sys.argv[2]).write_bytes(image[found:found + 48])
print('ЯДРО1-ВІДНЯТИ-ISA-ГОТОВО: машинний SUB знайдено у повному ELF64')
PY
timeout 8s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine" >"$TMP/asm"
grep -Eiq 'sub[[:space:]]+eax,r9d' "$TMP/asm"
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
SMALL=0;WIDE=0;ORACLE_PASS=0
# Обидва TSV файли від фізичного генератора містять 40 випадків.
# Виконуємо лише S-мітки оригінального Core1 віднімання; A-мітки іншої функції пропускаємо.
for cases in cases.tsv promotion.tsv;do
  while IFS=$'\t' read -r label head left right expected width;do
    [[ "$label" == s* ]] || continue
    test "$head" = 01011
    test "$width" = 12 || test "$width" = 24
    for cycle in 1 2;do
      timeout 7s "$ELF" <"$TMP/data/$label.frame" \
        >"$TMP/$label.$cycle.sens" 2>"$TMP/$label.$cycle.err"
      test ! -s "$TMP/$label.$cycle.err"
      cmp "$TMP/data/$label.expected.sens" "$TMP/$label.$cycle.sens"
      if [[ "$width" == 12 ]];then
        test "$(wc -c <"$TMP/$label.$cycle.sens")" -eq 3
      else
        test "$(wc -c <"$TMP/$label.$cycle.sens")" -eq 5
      fi
    done
    cmp "$TMP/$label.1.sens" "$TMP/$label.2.sens"
    if [[ -n "$ORACLE" ]];then
      printf '(відняти %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
      timeout 60s "$ORACLE" "$TMP/$label.lisp" \
        >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
      test ! -s "$TMP/$label.oracle.err"
      printf '%s\n' "$expected" >"$TMP/$label.oracle.expected"
      cmp "$TMP/$label.oracle.expected" "$TMP/$label.oracle.out"
      ORACLE_PASS=$((ORACLE_PASS+1))
    fi
    if [[ "$width" == 12 ]];then SMALL=$((SMALL+1))
    else WIDE=$((WIDE+1));fi
  done <"$TMP/data/$cases"
done
test "$SMALL" -eq 17 && test "$WIDE" -eq 3
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
NEG=0
for bad in empty short extra bad-first bad-middle text d1;do
  rc=0
  timeout 7s "$ELF" <"$TMP/data/$bad.frame" \
    >"$TMP/bad.out" 2>"$TMP/bad.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/bad.out"
  grep -Fq 'ВІДМОВА' "$TMP/bad.err"
  NEG=$((NEG+1))
done
test "$NEG" -eq 7
# Клієнт не має права перезаписати ані готовий ELF, ані symlink.
cp "$ELF" "$TMP/occupied.elf"
rc=0
timeout 60s "$TMP/bin/senscore1vidniatyadaptive" "$MODE" "$TMP/occupied.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$ELF" "$TMP/occupied.elf"
ln -s "$TMP/target.elf" "$TMP/dangling.elf"
rc=0
timeout 60s "$TMP/bin/senscore1vidniatyadaptive" "$MODE" "$TMP/dangling.elf" \
  >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/target.elf"
# Повторна працездатність після відмови на тому самому ELF.
timeout 7s "$ELF" <"$TMP/data/s01.frame" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/data/s01.expected.sens"
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 20;fi
echo "ЯДРО1-ВІДНЯТИ-ГОТОВО core1=1 native=40 d12=$SMALL d24=$WIDE oracle=$ORACLE_PASS negative=$NEG no-clobber=2 recovery=1 energy=NOT-MEASURED"
