#!/usr/bin/env bash
# G6.60 — чинний verified ExactIR D3:110 у справжньому файловому CLI.
# Жодного другого SENS lexer/evaluator; тільки вже доведений wsm.ircond.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git timeout cmp readelf stat; do
  command -v "$tool" >/dev/null || { echo "ФАЙЛОВА-УМОВА-БЛОК: $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ФАЙЛОВА-УМОВА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ФАЙЛОВА-УМОВА-БЛОК: потрібен справжній FPC' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
test -x "$ROOT/sens-oracle/target/debug/sens"

# Старий користувацький ET_EXEC CLI має бути повністю працездатним.
timeout 240s bash ./scripts/test-sensmashyna.sh
# Вже перевірені 8 машинних PIE + 18 негативів; саме тут незалежний
# upstream SENS працює з тим самим canonical T5M фізичним файлом.
timeout 300s bash ./scripts/test-ircond.sh

OUT="$ROOT/build/m0.2/ircond"
BIN="$ROOT/build/m0.2/mashyna-pie"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN/units" "$BIN/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$BIN/units" -FE"$BIN/bin" \
  -osensmashyna "$ROOT/src/sensmashyna.lpr"
CLI="$BIN/bin/sensmashyna"
test -x "$CLI"
COUNT=0
for name in порожня одна-хибна одна-істинна-0 одна-істинна-1 \
            друга-істинна-0 друга-істинна-1 перша-істинна обидві-хибні; do
  SOURCE="$OUT/$name.sens"
  PREVIOUS="$OUT/$name.elf"
  EXPECT="$OUT/$name.expected.sens"
  GENERATED="$TMP/$name.elf"
  test -s "$SOURCE" && test -s "$PREVIOUS" && test -s "$EXPECT"
  timeout 15s "$CLI" --умова-пі "$ROOT/external/sens" "$SOURCE" "$GENERATED" \
    >"$TMP/$name.cli.out" 2>"$TMP/$name.cli.err"
  # FPC -gh друкує власний heaptrc у stderr НАВІТЬ без витоків;
  # це не помилка CLI. Вимагати повного нуля, не приховувати діагностику.
  grep -Eq '^0 unfreed memory blocks : 0
  test -x "$GENERATED"
  test "$(stat -c '%a' "$GENERATED")" = 700
  cmp "$PREVIOUS" "$GENERATED"
  readelf -h "$GENERATED" >"$TMP/$name.header"
  readelf -l "$GENERATED" >"$TMP/$name.program"
  grep -F 'ELF64' "$TMP/$name.header" >/dev/null
  grep -Eq 'Type:.*DYN' "$TMP/$name.header"
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$name.header" >/dev/null
  grep -F 'LOAD' "$TMP/$name.program" >/dev/null
  timeout 5s "$GENERATED" >"$TMP/$name.actual.sens" 2>"$TMP/$name.machine.err"
  test ! -s "$TMP/$name.machine.err"
  cmp "$EXPECT" "$TMP/$name.actual.sens"
  test "$(wc -c <"$TMP/$name.actual.sens")" -eq 1
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 8

REJECTED=0
reject() {
  local out="$TMP/відмова.elf"
  local rc=0
  rm -f "$out"
  timeout 12s "$CLI" "$@" "$out" >"$TMP/reject.stdout" \
    2>"$TMP/reject.stderr" || rc=$?
  test "$rc" -eq 2 || {
    echo "ФАЙЛОВА-УМОВА-ПОМИЛКА: неправильний код відмови $rc" >&2
    exit 1
  }
  test ! -e "$out" && test ! -s "$TMP/reject.stdout"
  grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА:' "$TMP/reject.stderr" >/dev/null
  REJECTED=$((REJECTED+1))
}
printf '\363' > "$TMP/пошкоджений.sens"
cp "$OUT/порожня.sens" "$TMP/підміна.lisp"
cp "$OUT/порожня.expected.sens" "$TMP/голий-d3.sens"
reject --умова-пі "$ROOT/external/sens" "$TMP/пошкоджений.sens"
reject --умова-пі "$ROOT/external/sens" "$TMP/підміна.lisp"
reject --умова-пі "$ROOT/external/sens" "$TMP/голий-d3.sens"
reject --умова-пі "$ROOT/external/sens" "$TMP/відсутній.sens"
reject --умова-пі "$ROOT/external/sens" "$OUT/порожня.expected.sens"
reject --невідомий "$ROOT/external/sens" "$OUT/порожня.sens"

# Заборона перезапису раніше створеного ELF (включно з umask=000).
cp "$OUT/порожня.elf" "$TMP/зайнятий.elf"
rc=0
(umask 000; timeout 12s "$CLI" --умова-пі "$ROOT/external/sens" \
  "$OUT/порожня.sens" "$TMP/зайнятий.elf" >"$TMP/no-clobber.out" \
  2>"$TMP/no-clobber.err") || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/зайнятий.elf" "$OUT/порожня.elf"
REJECTED=$((REJECTED+1))
# Старий CLI--умова повинен і надалі створювати саме ET_EXEC.
timeout 15s "$CLI" --умова "$ROOT/external/sens" \
  "$OUT/порожня.sens" "$TMP/попередня-умова.elf" >"$TMP/legacy.out"
readelf -h "$TMP/попередня-умова.elf" | grep -Eq 'Type:.*EXEC'
timeout 5s "$TMP/попередня-умова.elf" > "$TMP/legacy.actual.sens"
cmp "$TMP/legacy.actual.sens" "$OUT/порожня.expected.sens"
test "$REJECTED" -eq 7
echo "ФАЙЛОВА-УМОВА-ПІ-ГАРАЗД CLI-PIE=$COUNT негативи=$REJECTED старий-ET_EXEC=так незалежний-SENS=$PIN"
 "$TMP/$name.cli.err"
  if grep -Fq 'НАТИВНИЙ-ELF-ПОМИЛКА:' "$TMP/$name.cli.err"; then
    echo "ФАЙЛОВА-УМОВА-ПОМИЛКА: CLI повідомив помилку в позитиві $name" >&2
    exit 1
  fi
  grep -F 'ELF-тип=3' "$TMP/$name.cli.out" >/dev/null
  test -x "$GENERATED"
  test "$(stat -c '%a' "$GENERATED")" = 700
  cmp "$PREVIOUS" "$GENERATED"
  readelf -h "$GENERATED" >"$TMP/$name.header"
  readelf -l "$GENERATED" >"$TMP/$name.program"
  grep -F 'ELF64' "$TMP/$name.header" >/dev/null
  grep -Eq 'Type:.*DYN' "$TMP/$name.header"
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$name.header" >/dev/null
  grep -F 'LOAD' "$TMP/$name.program" >/dev/null
  timeout 5s "$GENERATED" >"$TMP/$name.actual.sens" 2>"$TMP/$name.machine.err"
  test ! -s "$TMP/$name.machine.err"
  cmp "$EXPECT" "$TMP/$name.actual.sens"
  test "$(wc -c <"$TMP/$name.actual.sens")" -eq 1
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 8

REJECTED=0
reject() {
  local out="$TMP/відмова.elf"
  local rc=0
  rm -f "$out"
  timeout 12s "$CLI" "$@" "$out" >"$TMP/reject.stdout" \
    2>"$TMP/reject.stderr" || rc=$?
  test "$rc" -eq 2 || {
    echo "ФАЙЛОВА-УМОВА-ПОМИЛКА: неправильний код відмови $rc" >&2
    exit 1
  }
  test ! -e "$out" && test ! -s "$TMP/reject.stdout"
  grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА:' "$TMP/reject.stderr" >/dev/null
  REJECTED=$((REJECTED+1))
}
printf '\363' > "$TMP/пошкоджений.sens"
cp "$OUT/порожня.sens" "$TMP/підміна.lisp"
cp "$OUT/порожня.expected.sens" "$TMP/голий-d3.sens"
reject --умова-пі "$ROOT/external/sens" "$TMP/пошкоджений.sens"
reject --умова-пі "$ROOT/external/sens" "$TMP/підміна.lisp"
reject --умова-пі "$ROOT/external/sens" "$TMP/голий-d3.sens"
reject --умова-пі "$ROOT/external/sens" "$TMP/відсутній.sens"
reject --умова-пі "$ROOT/external/sens" "$OUT/порожня.expected.sens"
reject --невідомий "$ROOT/external/sens" "$OUT/порожня.sens"

# Заборона перезапису раніше створеного ELF (включно з umask=000).
cp "$OUT/порожня.elf" "$TMP/зайнятий.elf"
rc=0
(umask 000; timeout 12s "$CLI" --умова-пі "$ROOT/external/sens" \
  "$OUT/порожня.sens" "$TMP/зайнятий.elf" >"$TMP/no-clobber.out" \
  2>"$TMP/no-clobber.err") || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/зайнятий.elf" "$OUT/порожня.elf"
REJECTED=$((REJECTED+1))
# Старий CLI--умова повинен і надалі створювати саме ET_EXEC.
timeout 15s "$CLI" --умова "$ROOT/external/sens" \
  "$OUT/порожня.sens" "$TMP/попередня-умова.elf" >"$TMP/legacy.out"
readelf -h "$TMP/попередня-умова.elf" | grep -Eq 'Type:.*EXEC'
timeout 5s "$TMP/попередня-умова.elf" > "$TMP/legacy.actual.sens"
cmp "$TMP/legacy.actual.sens" "$OUT/порожня.expected.sens"
test "$REJECTED" -eq 7
echo "ФАЙЛОВА-УМОВА-ПІ-ГАРАЗД CLI-PIE=$COUNT негативи=$REJECTED старий-ET_EXEC=так незалежний-SENS=$PIN"
