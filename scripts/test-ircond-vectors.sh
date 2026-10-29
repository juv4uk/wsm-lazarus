#!/usr/bin/env bash
# G6.65 — повний truth-table pinned D3:110; енергія НЕ вимірюється.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for cmd in fpc git timeout cmp readelf sha256sum stat mktemp; do
  command -v "$cmd" >/dev/null || { echo "УМОВИ-ВЕКТОРИ-БЛОК: немає $cmd" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'УМОВИ-ВЕКТОРИ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
./scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
grep -Fq '(cond-clause . (test expression))' external/sens/contracts/language-contract-12.lisp
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'УМОВИ-ВЕКТОРИ-БЛОК: незалежний SENS oracle не зібраний' >&2; exit 127;
}
OUT="$ROOT/build/ircond-vectors"
mkdir -p "$OUT" "$OUT/units" "$OUT/bin"
LOG=$(mktemp)
trap 'rc=$?; if ((rc!=0)); then
 echo "УМОВИ-ВЕКТОРИ-ПРОВАЛ код=$rc" >&2; tail -n 50 "$LOG" >&2;
 for f in "$OUT/генератор.out" "$OUT/генератор.err" "$OUT/reject.err"; do
   if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 60 "$f" >&2; fi;
 done;
 fi; rm -f "$LOG"' EXIT
trap 'rc=$?; echo "УМОВИ-ВЕКТОРИ-ПОМИЛКА рядок=$LINENO код=$rc команда=$BASH_COMMAND" >&2' ERR
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-ircond-vectors "$ROOT/scripts/test-ircond-vectors.pas" >"$LOG" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -osensmashyna "$ROOT/src/sensmashyna.lpr" >"$LOG" 2>&1
timeout 30s "$OUT/bin/test-ircond-vectors" "$OUT" >"$OUT/генератор.out" 2>"$OUT/генератор.err"
grep -Fq 'КОМПІЛЯТОР-УМОВИ-СВІДКИ=21' "$OUT/генератор.out"
test -s "$OUT/перелік.tsv"
CLI="$OUT/bin/sensmashyna"
TMP_REPORT=$(mktemp "$OUT/неповний.XXXXXX")
printf 'форма\tдомен\tвхід_sha256\telf_sha256\tвідповідь_sha256\telf_байтів\tмашинний_тип\tенергія\n' >"$TMP_REPORT"
COUNT=0
FIRST=''
while IFS=$'\t' read -r name expected; do
  [[ "$name" =~ ^умова-[012]-[0-9][0-9]$ ]] || { echo 'Неправильна назва свідка' >&2; exit 1; }
  case "$expected" in 0|1|000) ;; *) echo 'Недопустима exact відповідь' >&2; exit 1;; esac
  SOURCE="$OUT/$name.sens"
  EXPECT="$OUT/$name.expected.sens"
  EXE="$OUT/$name.elf"
  EXE2="$OUT/$name-повтор.elf"
  test -s "$SOURCE" && test -s "$EXPECT"
  test -z "$FIRST" && FIRST="$SOURCE"
  timeout 20s "$CLI" --умова-пі "$ROOT/external/sens" "$SOURCE" "$EXE" \
    >"$OUT/$name.compile.out" 2>"$OUT/$name.compile.err"
  timeout 20s "$CLI" --умова-пі "$ROOT/external/sens" "$SOURCE" "$EXE2" \
    >"$OUT/$name.repeat.out" 2>"$OUT/$name.repeat.err"
  test -x "$EXE" && test -x "$EXE2"
  cmp "$EXE" "$EXE2"
  test "$(stat -c %a "$EXE")" = 700
  readelf -h "$EXE" >"$OUT/$name.header"
  grep -Eq 'Type:.*DYN' "$OUT/$name.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$OUT/$name.header"
  timeout 5s "$EXE" >"$OUT/$name.actual.sens" 2>"$OUT/$name.machine.err"
  test ! -s "$OUT/$name.machine.err"
  cmp "$EXPECT" "$OUT/$name.actual.sens"
  test "$(wc -c <"$OUT/$name.actual.sens")" -eq 1
  timeout 25s "$ORACLE" "$SOURCE" >"$OUT/$name.oracle.actual" 2>"$OUT/$name.oracle.err"
  test ! -s "$OUT/$name.oracle.err"
  cmp "$OUT/$name.oracle.txt" "$OUT/$name.oracle.actual"
  src_hash=$(sha256sum "$SOURCE"); src_hash=${src_hash%% *}
  elf_hash=$(sha256sum "$EXE"); elf_hash=${elf_hash%% *}
  ans_hash=$(sha256sum "$OUT/$name.actual.sens"); ans_hash=${ans_hash%% *}
  size=$(stat -c %s "$EXE")
  printf '%s\tD3:110\t%s\t%s\t%s\t%s\tET_DYN\tНЕ-ВИМІРЯНО\n' \
    "$name" "$src_hash" "$elf_hash" "$ans_hash" "$size" >>"$TMP_REPORT"
  COUNT=$((COUNT+1))
done <"$OUT/перелік.tsv"
test "$COUNT" -eq 21
test -n "$FIRST"

# Відмови компілятора не мають публікувати ELF або частковий stdout.
bad=0
reject() {
  local name="$1" source="$2" target="$OUT/відхилено-$1.elf" rc=0
  rm -f "$target"
  timeout 15s "$CLI" --умова-пі "$ROOT/external/sens" "$source" "$target" \
    >"$OUT/reject.out" 2>"$OUT/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -e "$target" && test ! -L "$target"
  test ! -s "$OUT/reject.out"
  grep -Fq 'ELF-' "$OUT/reject.err"
  bad=$((bad+1))
}
printf '\363' >"$OUT/пошкоджений.sens"
cp "$FIRST" "$OUT/підміна.lisp"
reject пошкоджений "$OUT/пошкоджений.sens"
reject д12 "$OUT/недопустимий-д12.sens"
reject текст "$OUT/підміна.lisp"
reject відсутній "$OUT/немає.sens"
# Записане раніше ELF не перезаписується, навіть якщо вхід знову коректний.
EXIST="$OUT/зайнятий.elf"
cp "$OUT/умова-0-00.elf" "$EXIST"
rc=0
timeout 15s "$CLI" --умова-пі "$ROOT/external/sens" "$FIRST" "$EXIST" \
  >"$OUT/no-clobber.out" 2>"$OUT/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$OUT/no-clobber.out"
cmp "$EXIST" "$OUT/умова-0-00.elf"
bad=$((bad+1))
test "$bad" -eq 5
mv "$TMP_REPORT" "$OUT/звіти.tsv"
echo "УМОВИ-ВЕКТОРИ-ГАРАЗД FPC=справжній ELF64=$COUNT oracle=$COUNT byte-exact=$COUNT повторних-ELF=$COUNT негативи=$bad джоулі=НЕ-ВИМІРЯНО"
# Джерела — exact .sens, результати — T5M, ELF — host compiled artifact.
# Звіт містить SHA256 і фізичні розміри; не приписує швидкість чи
# енерговитрати. Питання: чому один ELF результат без oracle не достатній?
# Чому запуск ELF двічі не доводить енергоефективність?
# Чому pinned D7 і D12 тут не отримують нового закону?