#!/usr/bin/env bash
# G6.68: реальні x86-64 ADD/IMUL із двійкових D12 свідків.
# Це admission gate, не вимір RAPL і не порівняння швидкості.
set -euo pipefail
trap 'code=$?; printf "D12-МАТРИЦЯ-ВІДМОВА: код=%d рядок=%d команда=%s\\n" "$code" "$LINENO" "$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-МАТРИЦЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "D12-МАТРИЦЯ-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
FPC_BIN=$(printenv FPC || echo fpc)
if [[ -v SENS_ORACLE_BIN ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = \
    2c498b35af53c085450eac6f51b87facf7f9aa47
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
for spec in \
  'scripts/test-d12-elf-matrytsia.pas test-d12-elf-matrytsia' \
  'src/sensd12elf.lpr sensd12elf' \
  'src/sensd12mul-elf.lpr sensd12mul-elf' \
  'src/senschyslo.lpr senschyslo'; do
  read -r path name <<< "$spec"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
      "-o$name" "$ROOT/$path" >"$TMP/build-$name.log" \
      2>"$TMP/build-$name.err"; then
    cat "$TMP/build-$name.log" "$TMP/build-$name.err" >&2; exit 1
  fi
  test -x "$TMP/bin/$name"
done
timeout 15s "$TMP/bin/test-d12-elf-matrytsia" "$TMP/свідки" \
  >"$TMP/матриця.tsv" 2>"$TMP/свідки.err"
if ! grep -Fq 'D12-МАТРИЦЯ-СВІДКИ-ГАРАЗД пар=36' "$TMP/свідки.err"; then
  echo 'D12-МАТРИЦЯ-ДІАГНОСТИКА: необроблений вивід фізичного FPC-генератора:' >&2
  cat "$TMP/свідки.err" >&2
  echo 'D12-МАТРИЦЯ-ДІАГНОСТИКА: перші рядки матриці:' >&2
  head -n 3 "$TMP/матриця.tsv" >&2
  exit 1
fi
test "$(wc -l < "$TMP/матриця.tsv")" -eq 36
ADD=0; OVERFLOW=0; MUL=0; WIDE=0; ORACLE=0
FIRST_ADD=''; FIRST_MUL=''
while IFS=$'\t' read -r name left right add_allowed width; do
  test -n "$name"
  [[ "$width" == 12 || "$width" == 24 ]]
  timeout 15s "$TMP/bin/sensd12mul-elf" --помножити-D12 \
    "$TMP/свідки/$name-l.sens" "$TMP/свідки/$name-r.sens" \
    "$TMP/$name-mul.elf" >"$TMP/mul.out" 2>"$TMP/mul.err"
  test ! -s "$TMP/mul.err"
  test -x "$TMP/$name-mul.elf"
  readelf -h "$TMP/$name-mul.elf" | grep -Eq 'Type:.*DYN'
  timeout 5s "$TMP/$name-mul.elf" > "$TMP/$name-mul-result.sens"
  cmp "$TMP/свідки/$name-mul.sens" "$TMP/$name-mul-result.sens"
  "$TMP/bin/senschyslo" --в-укр "D$width" \
    "$TMP/$name-mul-result.sens" > "$TMP/$name-mul.ukr"
  if [[ -v SENS_ORACLE_BIN ]]; then
    printf '(помножити %s %s)\n' "$left" "$right" > "$TMP/$name-mul.lisp"
    timeout 45s "$SENS_ORACLE_BIN" "$TMP/$name-mul.lisp" \
      > "$TMP/$name-mul.oracle" 2>"$TMP/$name-mul.oracle.err"
    test ! -s "$TMP/$name-mul.oracle.err"
    cmp "$TMP/$name-mul.ukr" "$TMP/$name-mul.oracle"
    ORACLE=$((ORACLE+1))
  fi
  if [[ -z "$FIRST_MUL" ]]; then FIRST_MUL="$name"; fi
  MUL=$((MUL+1))
  if [[ "$width" == 24 ]]; then WIDE=$((WIDE+1)); fi

  if [[ "$add_allowed" == так ]]; then
    timeout 15s "$TMP/bin/sensd12elf" --додати-D12 \
      "$TMP/свідки/$name-l.sens" "$TMP/свідки/$name-r.sens" \
      "$TMP/$name-add.elf" >"$TMP/add.out" 2>"$TMP/add.err"
    test ! -s "$TMP/add.err"
    test -x "$TMP/$name-add.elf"
    readelf -h "$TMP/$name-add.elf" | grep -Eq 'Type:.*DYN'
    timeout 5s "$TMP/$name-add.elf" > "$TMP/$name-add-result.sens"
    cmp "$TMP/свідки/$name-add.sens" "$TMP/$name-add-result.sens"
    "$TMP/bin/senschyslo" --в-укр D12 \
      "$TMP/$name-add-result.sens" > "$TMP/$name-add.ukr"
    if [[ -v SENS_ORACLE_BIN ]]; then
      printf '(додати %s %s)\n' "$left" "$right" > "$TMP/$name-add.lisp"
      timeout 45s "$SENS_ORACLE_BIN" "$TMP/$name-add.lisp" \
        > "$TMP/$name-add.oracle" 2>"$TMP/$name-add.oracle.err"
      test ! -s "$TMP/$name-add.oracle.err"
      cmp "$TMP/$name-add.ukr" "$TMP/$name-add.oracle"
      ORACLE=$((ORACLE+1))
    fi
    if [[ -z "$FIRST_ADD" ]]; then FIRST_ADD="$name"; fi
    ADD=$((ADD+1))
  else
    test "$add_allowed" == ні
    status=0
    timeout 15s "$TMP/bin/sensd12elf" --додати-D12 \
      "$TMP/свідки/$name-l.sens" "$TMP/свідки/$name-r.sens" \
      "$TMP/$name-add.elf" >"$TMP/add.out" 2>"$TMP/add.err" || status=$?
    test "$status" -ne 0
    test "$status" -ne 124
    test ! -e "$TMP/$name-add.elf"
    test ! -s "$TMP/add.out"
    grep -Fq 'ELF-D12-' "$TMP/add.err"
    OVERFLOW=$((OVERFLOW+1))
  fi
done < "$TMP/матриця.tsv"
test "$MUL" -eq 36
test "$ADD" -gt 0 && test "$OVERFLOW" -gt 0
test "$((ADD+OVERFLOW))" -eq 36
test "$WIDE" -gt 0
if [[ -v SENS_ORACLE_BIN ]]; then test "$ORACLE" -eq "$((MUL+ADD))"; fi

# Перевірені машинні інструкції, а не ELF із зашитою відповіддю.
tail -c +121 "$TMP/$FIRST_ADD-add.elf" > "$TMP/code-add"
tail -c +121 "$TMP/$FIRST_MUL-mul.elf" > "$TMP/code-mul"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code-add" > "$TMP/dis-add"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code-mul" > "$TMP/dis-mul"
grep -Eiq 'add[[:space:]]+eax,' "$TMP/dis-add"
grep -Eiq 'imul.*eax' "$TMP/dis-mul"
timeout 5s "$TMP/$FIRST_ADD-add.elf" > "$TMP/repeat-add.sens"
cmp "$TMP/$FIRST_ADD-add-result.sens" "$TMP/repeat-add.sens"
timeout 5s "$TMP/$FIRST_MUL-mul.elf" > "$TMP/repeat-mul.sens"
cmp "$TMP/$FIRST_MUL-mul-result.sens" "$TMP/repeat-mul.sens"

# No-clobber: не затираємо навіть повністю правильний існуючий ELF.
for mode in add mul; do
  if [[ "$mode" == add ]]; then
    first="$FIRST_ADD"; cmd="$TMP/bin/sensd12elf"; flag=--додати-D12
  else
    first="$FIRST_MUL"; cmd="$TMP/bin/sensd12mul-elf"; flag=--помножити-D12
  fi
  cp "$TMP/$first-$mode.elf" "$TMP/occupied-$mode.elf"
  status=0
  timeout 15s "$cmd" "$flag" "$TMP/свідки/$first-l.sens" \
    "$TMP/свідки/$first-r.sens" "$TMP/occupied-$mode.elf" \
    >"$TMP/occupied.out" 2>"$TMP/occupied.err" || status=$?
  test "$status" -ne 0
  test ! -s "$TMP/occupied.out"
  cmp "$TMP/$first-$mode.elf" "$TMP/occupied-$mode.elf"
done
echo "D12-МАШИННА-МАТРИЦЯ-ГАРАЗД пар=$MUL додавань=$ADD переповнень=$OVERFLOW W24=$WIDE oracle=$ORACLE RAPL=НЕ-ВИМІРЯНО"
