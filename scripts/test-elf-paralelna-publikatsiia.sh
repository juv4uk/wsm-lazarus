#!/usr/bin/env bash
# G6.66 — реальна гонка двох FPC компіляторів за ОДИН фізичний ELF.
# Ніякого нового SENS закону або припущення про джоулі / швидкодію.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-ГОНКА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for app in fpc timeout cmp readelf stat find git; do
  command -v "$app" >/dev/null || { echo "ЕЛФ-ГОНКА-БЛОК: немає $app" >&2; exit 127; }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
ORACLE="$ROOT/sens-oracle/target/release/sens"
test -x "$ORACLE" || { echo 'ЕЛФ-ГОНКА-БЛОК: немає незалежного SENS' >&2; exit 127; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# CI повинен називати конкретну першу відмову, не лише exit 1.
# Чинні негативні перевірки НЕ пропускаються.
trace_fail() {
  local rc=$?
  echo "ЕЛФ-ГОНКА-ДІАГНОСТИКА: код=$rc рядок=${BASH_LINENO[0]} команда=$BASH_COMMAND" >&2
  for log in "$TMP"/generator.log "$TMP"/generator.err \
             "$TMP"/*.oracle "$TMP"/*.oracle.err \
             "$TMP"/*.compile.out "$TMP"/*.compile.err \
             "$TMP"/p0.stdout "$TMP"/p0.stderr \
             "$TMP"/p1.stdout "$TMP"/p1.stderr; do
    if [[ -s "$log" ]]; then
      echo "--- $log ---" >&2
      tail -n 16 "$log" >&2
    fi
  done
  return "$rc"
}
trap trace_fail ERR
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
FPC_BIN=${FPC:-fpc}
for entry in 'src/sensmashyna.lpr sensmashyna' \
             'scripts/test-sensmashyna.pas test-sensmashyna'; do
  read -r source output <<< "$entry"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$output" \
    "$ROOT/$source" >"$TMP/$output.build.log" 2>&1 || {
      cat "$TMP/$output.build.log" >&2; exit 1;
    }
done
CLI="$TMP/bin/sensmashyna"
timeout 40s "$TMP/bin/test-sensmashyna" "$ROOT/external/sens" "$TMP/свідки" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
# Не вгадуємо мовний закон за ELF, а перевіряємо два ті самі джерела
# реальним незалежним pinned SENS ще ДО конкурентного запуску.
for pair in 'тотожні-00:1' 'тотожні-01:0'; do
  IFS=: read -r label answer <<< "$pair"
  timeout 50s "$ORACLE" "$TMP/свідки/$label.sens" >"$TMP/$label.oracle" \
    2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  test "$(tr -d '\r\n' <"$TMP/$label.oracle")" = "$answer"
  timeout 35s "$CLI" --тотожність "$ROOT/external/sens" \
    "$TMP/свідки/$label.sens" "$TMP/$label.reference.elf" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  test -x "$TMP/$label.reference.elf"
  readelf -h "$TMP/$label.reference.elf" | grep -Eq 'Type:.*DYN'
  timeout 10s "$TMP/$label.reference.elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/$label.actual.sens" "$TMP/свідки/$label.expected.sens"
done
# Не обов'язково хто переможе: обидва кандидати byte-exact підтверджені.
# Мають перемогти РІВНО один і тільки один, без неканонічної суміші.
SHARED="$TMP/спільний.elf"
ok=0
for ((round=1; round<=8; round++)); do
  rm -f "$SHARED"
  (
    set +e
    timeout 45s "$CLI" --тотожність "$ROOT/external/sens" \
      "$TMP/свідки/тотожні-00.sens" "$SHARED" \
      >"$TMP/p0.stdout" 2>"$TMP/p0.stderr"
    printf '%s\n' "$?" >"$TMP/p0.rc"
  ) &
  pid0=$!
  (
    set +e
    timeout 45s "$CLI" --тотожність "$ROOT/external/sens" \
      "$TMP/свідки/тотожні-01.sens" "$SHARED" \
      >"$TMP/p1.stdout" 2>"$TMP/p1.stderr"
    printf '%s\n' "$?" >"$TMP/p1.rc"
  ) &
  pid1=$!
  wait "$pid0"
  wait "$pid1"
  rc0=$(cat "$TMP/p0.rc")
  rc1=$(cat "$TMP/p1.rc")
  if [[ "$rc0" == 0 && "$rc1" == 2 ]]; then
    winner=0
  elif [[ "$rc0" == 2 && "$rc1" == 0 ]]; then
    winner=1
  else
    echo "ЕЛФ-ГОНКА-ПРОВАЛ: повтор=$round коди=$rc0/$rc1" >&2
    cat "$TMP/p0.stderr" "$TMP/p1.stderr" >&2
    exit 1
  fi
  loser=$((1-winner))
  test -s "$TMP/p$winner.stdout"
  # stdout Free Pascal залежить від host codepage: перевіряємо тільки
  # незмінний ASCII-маркер профілю; успіх доводить exit=0 + ELF + T5M.
  grep -Fq 'ELF64-x86-64' "$TMP/p$winner.stdout"
  test ! -s "$TMP/p$loser.stdout" || {
    echo 'ЕЛФ-ГОНКА-ПРОВАЛ: відхилений компілятор видав stdout' >&2; exit 1;
  }
  # Кодова сторінка хоста може показати кирилицю як '?'.
  # Механічний ASCII ELF64 лишається стабільною ознакою відмови.
  grep -Fq 'ELF64' "$TMP/p$loser.stderr"
  test -f "$SHARED" && test -x "$SHARED"
  test "$(stat -c '%a' "$SHARED")" = 700
  readelf -h "$SHARED" | grep -Eq 'Type:.*DYN'
  if cmp -s "$SHARED" "$TMP/тотожні-00.reference.elf"; then
    actual='тотожні-00'
  elif cmp -s "$SHARED" "$TMP/тотожні-01.reference.elf"; then
    actual='тотожні-01'
  else
    echo "ЕЛФ-ГОНКА-ПРОВАЛ: змішаний або змінений ELF повтор=$round" >&2
    exit 1
  fi
  timeout 10s "$SHARED" >"$TMP/race.actual.sens"
  cmp "$TMP/race.actual.sens" "$TMP/свідки/$actual.expected.sens"
  # mkstemp створює senXXXXXX у тій самій теці; не залишати сміття.
  if find "$TMP" -maxdepth 1 -type f -name 'sen??????' | grep -q .; then
    echo "ЕЛФ-ГОНКА-ПРОВАЛ: залишено приватний тимчасовий ELF" >&2
    exit 1
  fi
  ok=$((ok+1))
done

# І наявне ім'я, і dangling symlink мають лишатися недоторканними.
negative=0
reject_target() {
  local target="$1" status=0
  timeout 35s "$CLI" --тотожність "$ROOT/external/sens" \
    "$TMP/свідки/тотожні-01.sens" "$target" >"$TMP/reject.stdout" \
    2>"$TMP/reject.stderr" || status=$?
  test "$status" -eq 2
  test ! -s "$TMP/reject.stdout"
  grep -Fq 'ELF64' "$TMP/reject.stderr"
  negative=$((negative+1))
}
reject_target "$SHARED"
ln -s "$TMP/тотожні-00.reference.elf" "$TMP/посилання.elf"
reject_target "$TMP/посилання.elf"
test -L "$TMP/посилання.elf"
cmp "$TMP/тотожні-00.reference.elf" "$TMP/посилання.elf"
ln -s "$TMP/неіснуючий.elf" "$TMP/розірване.elf"
reject_target "$TMP/розірване.elf"
test -L "$TMP/розірване.elf" && test ! -e "$TMP/неіснуючий.elf"
test "$ok" -eq 8 && test "$negative" -eq 3
echo "ЕЛФ-ПАРАЛЕЛЬНА-ПУБЛІКАЦІЯ-ГАРАЗД пар=$ok процесів=16 відмов=$negative ELF=byte-exact oracle=pinned T5M=byte-exact mode=0700 залишків=0 енергія=НЕ-ВИМІРЯНО"
