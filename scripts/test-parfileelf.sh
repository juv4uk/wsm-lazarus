#!/usr/bin/env bash
# G6.156 — фізичні SENS тіла пари -> спільний машинний ELF64.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for exe in fpc git timeout cmp readelf grep mktemp wc cp stat;do
  command -v "$exe" >/dev/null || { echo "НЕМАЄ: $exe" >&2;exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010000 (ук парне?) (укр парне?)' >/dev/null
ORACLE="$(printenv SENS_ORACLE_BIN || true)"
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'ПОТРІБЕН-НЕЗАЛЕЖНИЙ-PINNED-SENS-ORACLE' >&2;exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc));then
    echo "ПАРА-ELF-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 22 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/u" "$TMP/physical"
for spec in \
 "src/sensparfileelf.lpr:sensparfileelf" \
 "scripts/test-parfile-fixtures.pas:test-parfile-fixtures";do
  IFS=: read -r source executable <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>&1 || {
      cat "$TMP/$executable.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$executable"
done
HEAPTRC="log=$TMP/fixture.heap" timeout 60s \
  "$TMP/bin/test-parfile-fixtures" "$ROOT" "$TMP/physical" \
  >"$TMP/manifest.tsv" 2>"$TMP/fixture.err"
test "$(wc -l <"$TMP/manifest.tsv")" -eq 7
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
test ! -s "$TMP/fixture.err"
P="$TMP/physical"
MODE=--скомпілювати-фізичну-пару
compile() {
  local argfile="$1" outfile="$2"
  HEAPTRC="log=$TMP/compile.heap" timeout 45s \
    "$TMP/bin/sensparfileelf" "$MODE" \
    "$P/тіло-а.sens" "$P/імя-а.sens" \
    "$P/тіло-б.sens" "$P/імя-б.sens" \
    "$P/параметр.sens" "$argfile" "$outfile"
}
# Незалежний pinned SENS CLI виконує той самий задукоментований
# алгоритм парної взаємної рекурсії як ДВА українські DEFINE.
# Текст — лише oracle-проєкція «укр»; machine input — тільки packed .sens.
# Числовий надрукований результат порівнюємо як математичне значення;
# це не дозвіл ототожнювати D12 з фізичним D24.
cat >"$TMP/oracle-definitions.lisp" <<'SENS'
(визначити парне
  (функція (величина)
    (за-умовою
      ((менше? величина 1) 1)
      (так (непарне (відняти величина 1))))))
(визначити непарне
  (функція (величина)
    (за-умовою
      ((менше? величина 1) 0)
      (так (парне (відняти величина 1))))))
SENS
passed=0;verified=0
while IFS=$'\t' read -r n expected;do
  test -n "$n"
  target="$TMP/$n.elf"
  compile "$P/arg-$n.sens" "$target" \
    >"$TMP/$n.compile.log" 2>"$TMP/$n.compile.err"
  grep -Fq 'result=D24_T5M_STDOUT' "$TMP/$n.compile.log"
  test ! -s "$TMP/$n.compile.err"
  test -x "$target"
  test "$(stat -c %a "$target")" = 700
  readelf -h "$target" >"$TMP/$n.elf.header"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$n.elf.header"
  if readelf -l "$target" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'НЕОЧІКУВАНИЙ-DYNAMIC-LOADER' >&2;exit 1;
  fi
  timeout 8s "$target" >"$TMP/$n.actual.sens" 2>"$TMP/$n.machine.err"
  test ! -s "$TMP/$n.machine.err"
  test "$(wc -c <"$TMP/$n.actual.sens")" -eq 5
  cmp "$TMP/$n.actual.sens" "$P/expected-$n.sens"
  compile "$P/arg-$n.sens" "$TMP/repeat-$n.elf" >"$TMP/$n.repeat.log"
  cmp "$target" "$TMP/repeat-$n.elf"
  cp "$TMP/oracle-definitions.lisp" "$TMP/$n.oracle.lisp"
  printf '(парне %s)\n' "$n" >>"$TMP/$n.oracle.lisp"
  timeout 60s "$ORACLE" "$TMP/$n.oracle.lisp" \
    >"$TMP/$n.oracle.out" 2>"$TMP/$n.oracle.err"
  test ! -s "$TMP/$n.oracle.err"
  printf '%s\n' "$expected" >"$TMP/$n.oracle.want"
  cmp "$TMP/$n.oracle.want" "$TMP/$n.oracle.out"
  passed=$((passed+1));verified=$((verified+1))
done <"$TMP/manifest.tsv"
test "$passed" -eq 7 && test "$verified" -eq 7

NEG=0
reject() {
  local label="$1";shift
  local dest="$TMP/invalid-$label.elf" rc=0
  HEAPTRC="log=$TMP/$label.heap" timeout 45s \
    "$TMP/bin/sensparfileelf" "$@" "$dest" \
    >"$TMP/$label.out" 2>"$TMP/$label.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.out"
  grep -Fq 'SENS-ПАРА-ELF64-ВІДМОВА:' "$TMP/$label.err"
  test ! -e "$dest" && test ! -L "$dest"
  NEG=$((NEG+1))
}
reject bad-width "$MODE" "$P/тіло-а.sens" "$P/імя-а.sens" \
 "$P/тіло-б.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/bad-width.sens"
reject bad-name "$MODE" "$P/тіло-а.sens" "$P/bad-name.sens" \
 "$P/тіло-б.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/arg-2.sens"
reject duplicate "$MODE" "$P/тіло-а.sens" "$P/імя-а.sens" \
 "$P/тіло-б.sens" "$P/імя-а.sens" "$P/параметр.sens" "$P/arg-2.sens"
reject shadow "$MODE" "$P/тіло-а.sens" "$P/імя-а.sens" \
 "$P/тіло-б.sens" "$P/імя-б.sens" "$P/імя-а.sens" "$P/arg-2.sens"
reject body "$MODE" "$P/тіло-а.sens" "$P/імя-а.sens" \
 "$P/bad-body.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/arg-2.sens"
for bad in bad-t5m bad-append empty;do
  reject "$bad" "$MODE" "$P/$bad.sens" "$P/імя-а.sens" \
   "$P/тіло-б.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/arg-2.sens"
done
cp "$P/тіло-а.sens" "$P/source.lisp"
reject projection "$MODE" "$P/source.lisp" "$P/імя-а.sens" \
 "$P/тіло-б.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/arg-2.sens"
reject missing "$MODE" "$P/absent.sens" "$P/імя-а.sens" \
 "$P/тіло-б.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/arg-2.sens"
reject mode --вигадано "$P/тіло-а.sens" "$P/імя-а.sens" \
 "$P/тіло-б.sens" "$P/імя-б.sens" "$P/параметр.sens" "$P/arg-2.sens"
test "$NEG" -eq 11
cp "$TMP/2.elf" "$TMP/occupied.elf"
rc=0
compile "$P/arg-2.sens" "$TMP/occupied.elf" \
 >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/2.elf"
ln -s "$TMP/not-here.elf" "$TMP/dangling.elf"
rc=0
compile "$P/arg-2.sens" "$TMP/dangling.elf" \
 >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/not-here.elf"
compile "$P/arg-8.sens" "$TMP/recovery.elf" >"$TMP/recovery.log"
timeout 8s "$TMP/recovery.elf" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$P/expected-8.sens"
echo "ПАРА-ФІЗИЧНИЙ-AOT-PASS machine=$passed oracle=$verified full-D24=$passed repeat=$passed negative=$NEG no-clobber=2 recovery=1 energy=NOT_MEASURED"
# Питання: 1) Чому повний ELF має збігатися byte-for-byte?
# 2) Чому pinned D6 oracle перевіряє парність, не семантику двох DEFINE?
# 3) Чому D24 stdout не заміняємо десятковим UTF-8?
# 4) Чому ця підмножина не є повним компілятором Core1?
