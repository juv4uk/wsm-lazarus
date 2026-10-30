#!/usr/bin/env bash
# G6.248 — один фізичний .sens → один ELF64 за паралельних CLI.
# Host filesystem atomicity, НЕ SENS семантика чи нові функції.
# 1) Чому єдиний успіх є умовою no-clobber?
# 2) Чому атомарна публікація не тотожна точності SENS?
# 3) Чому важливі виконання ELF і фізичні T5M-байти?
# 4) Чому права 0700 перевіряємо за umask=000?
# 5) Чому три профілі не доводять весь Core1?
set -Eeuo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for tool in git fpc timeout cmp grep readelf stat mktemp find sleep wc; do
  command -v "$tool" >/dev/null || {
    echo "КОНКУРЕНТНИЙ-ELF-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
finish() {
  rc=$?
  if ((rc)); then
    echo "КОНКУРЕНТНИЙ-ELF-ПРОВАЛ код=$rc" >&2
    for file in "$TMP"/*.build "$TMP"/*.err; do
      if [[ -s "$file" ]]; then echo "--- $file" >&2; tail -n 20 "$file" >&2; fi
    done
    echo "КОНКУРЕНТНИЙ-ELF-ДІАГНОСТИКА: ${LAST_FAILURE:-завершено без ERR trap}" >&2
  fi
  rm -rf "$TMP"
}
trap finish EXIT
trap 'rc=$?; LAST_FAILURE="рядок=$LINENO код=$rc команда=$BASH_COMMAND"' ERR
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/out"
for row in \
  'scripts/test-sensmashyna.pas test-sensmashyna' \
  'src/sensmashyna.lpr sensmashyna'; do
  read -r source name <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
    cat "$TMP/$name.build" >&2; exit 1;
  }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-sensmashyna" "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
# Точний доказ — фізичні файли, а не кодування host WriteLn у лог.
test -s "$TMP/fixtures.log"
test "$(find "$TMP/physical" -maxdepth 1 -type f -name '*.expected.sens' | wc -l)" -eq 8
for sample in 'цитата-д7' 'цитата-список' 'атом-один' 'атом-пара' \
              'тотожні-00' 'тотожні-01' 'тотожні-10' 'тотожні-11'; do
  test -s "$TMP/physical/$sample.sens"
  test -s "$TMP/physical/$sample.expected.sens"
done
CLI="$TMP/bin/sensmashyna"
umask 000
PROFILES=0
SUCCESSES=0
REJECTIONS=0
for profile in 'цитата:цитата-д7' 'атом:атом-один' 'тотожність:тотожні-00'; do
  IFS=: read -r mode sample <<<"$profile"
  source="$TMP/physical/$sample.sens"
  expected="$TMP/physical/$sample.expected.sens"
  reference="$TMP/reference-$mode.elf"
  target="$TMP/out/$mode.elf"
  test -s "$source" && test -s "$expected"
  timeout 25s "$CLI" "--$mode" "$ROOT/external/sens" "$source" "$reference" \
    >"$TMP/reference-$mode.log" 2>"$TMP/reference-$mode.err"
  test -x "$reference"
  test "$(stat -c '%a' "$reference")" = 700
  readelf -h "$reference" >"$TMP/reference-$mode.header"
  grep -Fq ELF64 "$TMP/reference-$mode.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/reference-$mode.header"
  gate="$TMP/start-$mode"
  pids=""
  for i in 1 2 3 4 5 6 7 8; do
    (
      while [[ ! -e "$gate" ]]; do sleep 0.01; done
      status=0
      timeout 25s "$CLI" "--$mode" "$ROOT/external/sens" "$source" "$target" \
        >"$TMP/run-$mode-$i.log" 2>"$TMP/run-$mode-$i.err" || status=$?
      printf '%s\n' "$status" >"$TMP/run-$mode-$i.status"
    ) &
    pids="$pids $!"
  done
  : >"$gate"
  for pid in $pids; do wait "$pid"; done
  # FPC може перекодувати кириличні літерали WriteLn як '?'.
  # Перевіряємо стабільну частину успішного машинного профілю та
  # повний реальний текст помилки no-clobber, не вимикаючи жодного негативу.
  accepted=0
  refused=0
  for i in 1 2 3 4 5 6 7 8; do
    code="$(cat "$TMP/run-$mode-$i.status")"
    case "$code" in
      0)
        grep -Fq 'ELF64-x86-64' "$TMP/run-$mode-$i.log"
        accepted=$((accepted+1))
        ;;
      2)
        test ! -s "$TMP/run-$mode-$i.log"
        grep -Fq 'Ціль ELF64 уже існує або захищена' "$TMP/run-$mode-$i.err"
        refused=$((refused+1))
        ;;
      *)
        echo "КОНКУРЕНТНИЙ-ELF-ПРОВАЛ профіль=$mode процес=$i код=$code" >&2
        exit 1
        ;;
    esac
  done
  [[ "$accepted" -eq 1 && "$refused" -eq 7 ]] || {
    echo "КОНКУРЕНТНИЙ-ELF-ПРОВАЛ профіль=$mode успіх=$accepted відмов=$refused" >&2
    exit 1
  }
  cmp "$reference" "$target"
  test "$(stat -c '%a' "$target")" = 700
  test -x "$target"
  timeout 5s "$target" >"$TMP/$mode.actual.sens" 2>"$TMP/$mode.machine.err"
  test ! -s "$TMP/$mode.machine.err"
  cmp "$expected" "$TMP/$mode.actual.sens"
  test -z "$(find "$TMP/out" -maxdepth 1 -name 'sen??????' -print -quit)"
  rc=0
  timeout 20s "$CLI" "--$mode" "$ROOT/external/sens" "$source" "$target" \
    >"$TMP/retry-$mode.log" 2>"$TMP/retry-$mode.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/retry-$mode.log"
  cmp "$reference" "$target"
  recovery="$TMP/out/$mode-recovery.elf"
  timeout 20s "$CLI" "--$mode" "$ROOT/external/sens" "$source" "$recovery" \
    >"$TMP/recovery-$mode.log" 2>"$TMP/recovery-$mode.err"
  cmp "$reference" "$recovery"
  test "$(stat -c '%a' "$recovery")" = 700
  timeout 5s "$recovery" >"$TMP/$mode.recovery.sens"
  cmp "$expected" "$TMP/$mode.recovery.sens"
  PROFILES=$((PROFILES+1))
  SUCCESSES=$((SUCCESSES+accepted))
  REJECTIONS=$((REJECTIONS+refused))
done
[[ "$PROFILES" -eq 3 && "$SUCCESSES" -eq 3 && "$REJECTIONS" -eq 21 ]]
test -z "$(find "$TMP/out" -maxdepth 1 -name 'sen??????' -print -quit)"
echo 'VERIFIED-ELFPUBLISH-CONCURRENT-PASS FPC=checked profiles=3 competitors=24 winner=3 rejected=21 native=3 recoveries=3 mode=0700 no-clobber=yes oracle=EXISTING-FIXTURES energy=NOT-MEASURED'
