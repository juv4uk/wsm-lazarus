#!/usr/bin/env bash
# G6.43 — два справжніх FPC/Linux процеси конкурують за ОДНЕ нове
# фізичне ім'я .sens. Тільки механіка атомарного inode; не REPL oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc timeout cmp stat mktemp find; do
  command -v "$tool" >/dev/null || {
    echo "ЗМАГАННЯ-ФІЗИЧНОЇ-ВІДПОВІДІ-БЛОК: відсутній $tool" >&2
    exit 127
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЗМАГАННЯ-ФІЗИЧНОЇ-ВІДПОВІДІ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh

# Зберігаємо всю чинну реальну регресію без пропусків:
# G6.39: 10 справжніх машинних ELF + 22 негативи;
# G6.42: 22 ELF + 27 негативів + 36 ELF64 geometry мутацій.
timeout 240s bash ./scripts/test-senselfvykon.sh
CLI="$ROOT/build/m0.2/senselfvykon/bin/senselfvykon"
GEN="$ROOT/build/m0.2/senselfvykon/bin/test-senselfvykon"
test -x "$CLI" && test -x "$GEN"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/джерела" "$TMP/відповіді" "$TMP/журнали"
timeout 20s "$GEN" "$TMP/джерела" >"$TMP/журнали/джерела.out"
test -s "$TMP/джерела/p01.sens"
test -s "$TMP/джерела/p02.sens"
# D7 SYN — 0010110, 7-бітні ДАНІ після D3:001 quote, не opcode;
# другий вхід — цитований D1:1. Виходи фізично різні:
if cmp -s "$TMP/джерела/p01.expected.sens" \
    "$TMP/джерела/p02.expected.sens"; then
  echo 'ЗМАГАННЯ-ПОМИЛКА: фізичні результати різних доменів збіглися' >&2
  exit 1
fi
cp "$TMP/джерела/p01.sens" "$TMP/журнали/оригінал-7.sens"
cp "$TMP/джерела/p02.sens" "$TMP/журнали/оригінал-1.sens"

# Кожне коло має окрему ціль. Одночасність — ДВА справжні child
# процеси, а не послідовні тести "спочатку FileExists, потім rename".
ROUNDS=24
FIRST=0
SECOND=0
for ((round=1; round<=ROUNDS; round++)); do
  dest="$TMP/відповіді/відповідь-$round.sens"
  test ! -e "$dest"
  timeout 12s "$CLI" --цитата "$ROOT/external/sens" \
    "$TMP/джерела/p01.sens" "$dest" \
    >"$TMP/журнали/$round-7.out" 2>"$TMP/журнали/$round-7.err" &
  pid7=$!
  timeout 12s "$CLI" --цитата "$ROOT/external/sens" \
    "$TMP/джерела/p02.sens" "$dest" \
    >"$TMP/журнали/$round-1.out" 2>"$TMP/журнали/$round-1.err" &
  pid1=$!
  if wait "$pid7"; then status7=0; else status7=$?; fi
  if wait "$pid1"; then status1=0; else status1=$?; fi

  # Лише один процес створює нову директорну назву fpLink.
  # Другий ЗОБОВ'ЯЗАНИЙ отримати fail-closed exit 2, а не timeout.
  if ((status7==0 && status1==2)); then
    cmp "$dest" "$TMP/джерела/p01.expected.sens"
    good="$TMP/журнали/$round-7.out"
    badout="$TMP/журнали/$round-1.out"
    baderr="$TMP/журнали/$round-1.err"
    FIRST=$((FIRST+1))
  elif ((status1==0 && status7==2)); then
    cmp "$dest" "$TMP/джерела/p02.expected.sens"
    good="$TMP/журнали/$round-1.out"
    badout="$TMP/журнали/$round-7.out"
    baderr="$TMP/журнали/$round-7.err"
    SECOND=$((SECOND+1))
  else
    echo "ЗМАГАННЯ-ПОМИЛКА: коло=$round D7=$status7 D1=$status1" >&2
    cat "$TMP/журнали/$round-7.err" "$TMP/журнали/$round-1.err" >&2
    exit 1
  fi
  test -s "$dest"
  test "$(stat -c '%a' "$dest")" = 600 || {
    echo "ЗМАГАННЯ-ПОМИЛКА: порушено приватні права коло=$round" >&2
    exit 1
  }
  grep -Fq 'T5M=' "$good"
  test ! -s "$badout"
  grep -Fq 'МАШИННЕ-ELF-ПОМИЛКА:' "$baderr" || {
    echo "ЗМАГАННЯ-ПОМИЛКА: втрачено діагностику коло=$round" >&2
    exit 1
  }

  # Третя спроба не може змінити вже опубліковані байти чи
  # залишити застарілий stdout. Зберігаємо фізичний свідок цілі.
  cp "$dest" "$TMP/журнали/$round-locked.sens"
  if timeout 12s "$CLI" --цитата "$ROOT/external/sens" \
    "$TMP/джерела/p02.sens" "$dest" \
    >"$TMP/журнали/$round-retry.out" \
    2>"$TMP/журнали/$round-retry.err"; then
    echo "ЗМАГАННЯ-ПОМИЛКА: повторний перезапис коло=$round" >&2
    exit 1
  fi
  test ! -s "$TMP/журнали/$round-retry.out"
  grep -Fq 'МАШИННЕ-ELF-ПОМИЛКА:' "$TMP/журнали/$round-retry.err"
  cmp "$dest" "$TMP/журнали/$round-locked.sens"
  test -z "$(find "$TMP/відповіді" -maxdepth 1 -type f -name 'sen*.tmp' -print)"
done
test "$((FIRST+SECOND))" -eq "$ROUNDS"

# На тому самому фізичному шляху source=destination опублікувати
# результат означало б знищити canonical source; fpLink відмовляє.
if timeout 12s "$CLI" --цитата "$ROOT/external/sens" \
  "$TMP/джерела/p01.sens" "$TMP/джерела/p01.sens" \
  >"$TMP/журнали/same.out" 2>"$TMP/журнали/same.err"; then
  echo 'ЗМАГАННЯ-ПОМИЛКА: змінено вхідний .sens на місці' >&2
  exit 1
fi
test ! -s "$TMP/журнали/same.out"
grep -Fq 'МАШИННЕ-ELF-ПОМИЛКА:' "$TMP/журнали/same.err"
cmp "$TMP/джерела/p01.sens" "$TMP/журнали/оригінал-7.sens"
cmp "$TMP/джерела/p02.sens" "$TMP/журнали/оригінал-1.sens"
test -z "$(find "$TMP" -type f -name 'sen*.tmp' -print)"

echo "ЗМАГАННЯ-ФІЗИЧНИХ-ВІДПОВІДЕЙ-ГАРАЗД pin=$PIN кола=$ROUNDS процеси=$((ROUNDS*2)) рівно-один-переможець=так D7=$FIRST D1=$SECOND приватність=0600 no-clobber=так same-path=відхилено temp=0 T5M=точний регресія-ELF=22"

# Представлення та власність: p01/p02 .sens — незмінні фізичні T5M
# байти; результатом кожної гонки є одна нова hard-linked POSIX inode
# з правами 0600. Обидва незалежні PID є власністю shell wait;
# FPC/ELF child і тимчасовий exec-каталог прибирає wsm.elfprobe.
# Усі наші witness/журнали — приватні файли у TMP з trap cleanup.
# Питання:
# 1) Чому два PID потрібні для доведення атомарності, а FileExists ні?
# 2) Чому D7 SYN не можна порівнювати як D1, навіть якщо 1 байт?
# 3) Чому програш дозволено тільки з exit=2, а не 124 timeout?
# 4) Чому fpLink захищає ціль, але не доводить semantic SENS REPL parity?
# 5) Чому не можна повторно публікувати навіть тотожні T5M байти?
