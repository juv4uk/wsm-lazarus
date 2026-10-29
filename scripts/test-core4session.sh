#!/usr/bin/env bash
# G5.16: перевірка FPC і реального постійного сеансу вузького pinned Core4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE4-СЕАНС-БЛОКЕР: немає FPC' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-session-units build/m0.2/bin
for SOURCE in test-core4session sensseanscore4; do
  case "$SOURCE" in
    test-core4session) FILE="$ROOT/scripts/test-core4session.pas" ;;
    sensseanscore4) FILE="$ROOT/src/sensseanscore4.lpr" ;;
  esac
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
    -o"$SOURCE" "$FILE"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$ROOT/build/m0.2/bin/test-core4session" "$ROOT" "$TMP"
BIN="$ROOT/build/m0.2/bin/sensseanscore4"
{
  printf '%s\n' "$TMP/01-tak.sens" "$TMP/02-nevidome.sens" \
    "$TMP/03-ni.sens" "$TMP/04-d24-argument.sens" \
    "$TMP/05-global-d24-0.sens" "$TMP/06-poshkodzhenyi.sens" \
    "$TMP/07-global-d24-1.sens" "$TMP/08-vidsutnii.sens" \
    "$TMP/09-povtornyi.sens" ':вихід'
} > "$TMP/session.in"
set +e
"$BIN" --сеанс "$ROOT" < "$TMP/session.in" > "$TMP/out" 2> "$TMP/err"
RC=$?
set -e
test "$RC" -eq 2 || { echo "очікувався код 2 за трьох відмов; отримано $RC" >&2; exit 1; }
cat > "$TMP/expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000001
РЕЗУЛЬТАТ 5 24:000000000000000000000000
РЕЗУЛЬТАТ 7 24:000000000000000000000001
РЕЗУЛЬТАТ 9 1:1
EOF
diff -u "$TMP/expected" "$TMP/out"
test "$(grep -c '^ПОМИЛКА ' "$TMP/err")" -eq 3
grep -q '^ПОМИЛКА 2 ' "$TMP/err"
grep -q '^ПОМИЛКА 6 ' "$TMP/err"
grep -q '^ПОМИЛКА 8 ' "$TMP/err"
! grep -q '^РЕЗУЛЬТАТ 2 ' "$TMP/out"
! grep -q '^РЕЗУЛЬТАТ 6 ' "$TMP/out"
! grep -q '^РЕЗУЛЬТАТ 8 ' "$TMP/out"
{
  printf '%s\n' "$TMP/01-tak.sens" ':вихід' "$TMP/03-ni.sens"
} > "$TMP/early-exit.in"
"$BIN" --сеанс "$ROOT" < "$TMP/early-exit.in" > "$TMP/early-exit.out" 2> "$TMP/early-exit.err"
printf 'РЕЗУЛЬТАТ 1 1:1\n' > "$TMP/early-exit.expected"
diff -u "$TMP/early-exit.expected" "$TMP/early-exit.out"
! grep -q '^ПОМИЛКА ' "$TMP/early-exit.err"
# -gh лишено ввімкненим: окремо перевіряємо нуль незвільнених блоків.
grep -q '0 unfreed memory blocks' "$TMP/early-exit.err"
grep -q '0 unfreed memory blocks' "$TMP/err"
set +e
"$BIN" --невідомо "$ROOT" > "$TMP/invalid.out" 2> "$TMP/invalid.err"
INVALID_RC=$?
"$BIN" --сеанс "$TMP/non-existent-authority" < /dev/null > "$TMP/no-root.out" 2> "$TMP/no-root.err"
ROOT_RC=$?
set -e
test "$INVALID_RC" -eq 64
test "$ROOT_RC" -eq 2
test ! -s "$TMP/invalid.out"
test ! -s "$TMP/no-root.out"
# G5.17: два початкові двійкові виклики, а потім stdin в одному runtime.
printf '%s\n' "$TMP/03-ni.sens" ':вихід' >"$TMP/startup.in"
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --завантажити "$TMP/05-global-d24-0.sens" \
  <"$TMP/startup.in" >"$TMP/startup.out" 2>"$TMP/startup.err"
cat >"$TMP/startup.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 24:000000000000000000000000
РЕЗУЛЬТАТ 3 1:0
EOF
diff -u "$TMP/startup.expected" "$TMP/startup.out"
grep -q '0 unfreed memory blocks' "$TMP/startup.err"

# Пізня відмова до stdin не публікує навіть раніше виконаний startup.
set +e
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --завантажити "$TMP/06-poshkodzhenyi.sens" \
  <"$TMP/startup.in" >"$TMP/late.out" 2>"$TMP/late.err"
LATE_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --завантажити "$TMP/08-vidsutnii.sens" \
  <"$TMP/startup.in" >"$TMP/missing.out" 2>"$TMP/missing.err"
MISSING_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --завантажити "$TMP/startup.in" <"$TMP/startup.in" \
  >"$TMP/wrong-ext.out" 2>"$TMP/wrong-ext.err"
WRONG_EXT_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити \
  >"$TMP/odd.out" 2>"$TMP/odd.err"
ODD_RC=$?
"$BIN" --сеанс "$ROOT" --не-виклик "$TMP/01-tak.sens" \
  >"$TMP/flag.out" 2>"$TMP/flag.err"
FLAG_RC=$?
set -- --сеанс "$ROOT"
for ((i=0;i<33;i++)); do set -- "$@" --завантажити "$TMP/01-tak.sens"; done
"$BIN" "$@" <"$TMP/startup.in" >"$TMP/limit.out" 2>"$TMP/limit.err"
LIMIT_RC=$?
set -e
test "$LATE_RC" -eq 2 && test "$MISSING_RC" -eq 2 &&
  test "$WRONG_EXT_RC" -eq 2 && test "$ODD_RC" -eq 64 &&
  test "$FLAG_RC" -eq 64 && test "$LIMIT_RC" -eq 64
for name in late missing wrong-ext odd flag limit; do
  test ! -s "$TMP/$name.out"
done
grep -Fq 'ПОМИЛКА ЗАВАНТАЖЕННЯ CORE4:' "$TMP/late.err"
grep -Fq 'ПОМИЛКА ЗАВАНТАЖЕННЯ CORE4:' "$TMP/missing.err"
grep -Fq 'фізичного .sens' "$TMP/wrong-ext.err"
grep -q '0 unfreed memory blocks' "$TMP/late.err"
echo 'CORE4-ПОЧАТКОВІ-ФОРМИ-ГАРАЗД startup=2 stdin=1 пізня-відмова=атомарно межа=32'
# G5.17: 48 MiB фізичного stdin в одному рядку не повинен накопичуватись
# у пам'яті. Після відхилення весь наступний запит лишається придатним.
command -v python3 >/dev/null || { echo 'CORE4-СЕАНС-БЛОКЕР: немає Python3 для генератора host-вводу' >&2; exit 127; }
python3 - "$TMP/bounded.in" "$TMP/01-tak.sens" "$TMP/03-ni.sens" \
    "$TMP/06-poshkodzhenyi.sens" "$TMP/09-povtornyi.sens" <<'PY'
import os
import sys
destination, first, after, broken, final = map(os.fsencode, sys.argv[1:])
with open(destination, "wb") as f:
    f.write(first + b"\n")
    f.write(b"x" * (4096 - 5) + b".sens\n")  # рівно 4096 байтів
    f.write(b"x" * (4097 - 5) + b".sens\n")  # перша недопустима довжина
    f.write(b"x" * (48 * 1024 * 1024) + b".sens\n")
    f.write(b"\r\n")  # порожній CRLF — не запит
    f.write(after + b"\r\n")  # реальне виконання після відмови
    f.write(broken + b"\n")
    f.write(final)  # остання фізична форма без LF
PY
# Вимірюємо ПІК РЕЗИДЕНТНОЇ пам'яті (RSS), а не віртуальний
# адресний простір FPC. Сталий базовий runtime може резервувати більше
# 64 MiB віртуально, не використовуючи стільки фізичної пам'яті.
[ -x /usr/bin/time ] || { echo 'CORE4-СЕАНС-БЛОКЕР: немає /usr/bin/time' >&2; exit 127; }
set +e
/usr/bin/time -f '%M' -o "$TMP/baseline.rss" \
  "$BIN" --сеанс "$ROOT" < /dev/null > "$TMP/limitcheck.out" 2> "$TMP/limitcheck.err"
BASE_RC=$?
if [ "$BASE_RC" -ne 0 ]; then
  echo "неочікувана помилка порожнього сеансу: $BASE_RC" >&2
  tail -c 2200 "$TMP/limitcheck.err" >&2 || true
  exit 1
fi
/usr/bin/time -f '%M' -o "$TMP/bounded.rss" \
  "$BIN" --сеанс "$ROOT" < "$TMP/bounded.in" > "$TMP/bounded.out" 2> "$TMP/bounded.err"
BOUNDED_RC=$?
set -e
# GNU time додає рядок із кодом 2 перед RSS для навмисно негативного сеансу.
BASE_RSS=$(tail -n 1 "$TMP/baseline.rss")
BOUNDED_RSS=$(tail -n 1 "$TMP/bounded.rss")
case "$BASE_RSS:$BOUNDED_RSS" in
  *[!0-9:]*|'') echo 'нечислові вимірювання RSS' >&2; exit 1 ;;
esac
# 8 MiB дельта не допускає безконтрольного 48 MiB накопичення.
test "$BOUNDED_RSS" -le "$((BASE_RSS + 8192))" || {
  echo "піковий RSS виріс понад 8 MiB: базовий=$BASE_RSS довгий=$BOUNDED_RSS KiB" >&2
  exit 1
}
if [ "$BOUNDED_RC" -ne 2 ]; then
  echo "необмежений ввід або неочікуваний статус: $BOUNDED_RC" >&2
  echo '--- Обмежена діагностика stderr (кінець) ---' >&2
  tail -c 2200 "$TMP/bounded.err" >&2 || true
  echo '--- Кінець stderr ---' >&2
  exit 1
fi
cat > "$TMP/bounded.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 5 1:0
РЕЗУЛЬТАТ 7 1:1
EOF
diff -u "$TMP/bounded.expected" "$TMP/bounded.out"
test "$(grep -c '^ПОМИЛКА ' "$TMP/bounded.err")" -eq 4
for N in 2 3 4 6; do
  grep -q "^ПОМИЛКА $N " "$TMP/bounded.err"
done
! grep '^ПОМИЛКА 2 ' "$TMP/bounded.err" | grep -q 'межа=4096'
grep '^ПОМИЛКА 3 ' "$TMP/bounded.err" | grep -q 'межа=4096'
grep '^ПОМИЛКА 4 ' "$TMP/bounded.err" | grep -q 'межа=4096'
grep -q '0 unfreed memory blocks' "$TMP/bounded.err"
echo 'CORE4-СЕАНС-ГАРАЗД успішних=6 негативних=5 відновлення=так середовище=один-процес'


# G5.19: фізичний startup-пакет (багато D2 коренів) у ТОМУ САМОМУ runtime.
# Старий G5.16–G5.18 bounded stdin, RSS та негативний набір лишаються вище.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4session-batch "$ROOT/scripts/test-core4session-batch.pas"
"$ROOT/build/m0.2/bin/test-core4session-batch" "$TMP"
printf '%s\n' "$TMP/07-global-d24-1.sens" ':вихід' > "$TMP/batch-session.in"
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --завантажити-пакет "$TMP/paket3.sens" \
  --завантажити "$TMP/03-ni.sens" \
  < "$TMP/batch-session.in" > "$TMP/batch-session.out" 2> "$TMP/batch-session.err"
cat > "$TMP/batch-session.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000000
РЕЗУЛЬТАТ 5 1:0
РЕЗУЛЬТАТ 6 24:000000000000000000000001
EOF
diff -u "$TMP/batch-session.expected" "$TMP/batch-session.out"
grep -q '0 unfreed memory blocks' "$TMP/batch-session.err"

# 64 допустимих форм: усі справді виконано і stdin стартує із №65.
printf '%s\n' "$TMP/03-ni.sens" ':вихід' > "$TMP/batch64.in"
"$BIN" --сеанс "$ROOT" --завантажити-пакет "$TMP/paket64.sens" \
  < "$TMP/batch64.in" > "$TMP/batch64.out" 2> "$TMP/batch64.err"
: > "$TMP/batch64.expected"
for ((i=1;i<=64;i++)); do
  printf 'РЕЗУЛЬТАТ %d 1:1\n' "$i" >> "$TMP/batch64.expected"
done
printf 'РЕЗУЛЬТАТ 65 1:0\n' >> "$TMP/batch64.expected"
diff -u "$TMP/batch64.expected" "$TMP/batch64.out"
grep -q '0 unfreed memory blocks' "$TMP/batch64.err"

# 65-й D2 корінь, третій невідомий D7, неканонічні байти, порожнє,
# відсутній фізичний файл та людська .lisp-проєкція відхиляються атомарно.
set +e
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --завантажити-пакет "$TMP/paket-pomylka.sens" \
  < "$TMP/batch64.in" > "$TMP/batch-late.out" 2> "$TMP/batch-late.err"
LATE_BATCH_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити-пакет "$TMP/paket65.sens" \
  < "$TMP/batch64.in" > "$TMP/batch65.out" 2> "$TMP/batch65.err"
BATCH65_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити-пакет "$TMP/paket-nekorektne.sens" \
  < "$TMP/batch64.in" > "$TMP/batch-corrupt.out" 2> "$TMP/batch-corrupt.err"
CORRUPT_BATCH_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити-пакет "$TMP/paket-porozhnie.sens" \
  < "$TMP/batch64.in" > "$TMP/batch-empty.out" 2> "$TMP/batch-empty.err"
EMPTY_BATCH_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити-пакет "$TMP/missing.sens" \
  < "$TMP/batch64.in" > "$TMP/batch-missing.out" 2> "$TMP/batch-missing.err"
MISSING_BATCH_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити-пакет "$ROOT/external/sens/lib/core4.lisp" \
  < "$TMP/batch64.in" > "$TMP/batch-lisp.out" 2> "$TMP/batch-lisp.err"
LISP_BATCH_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити-пакет \
  > "$TMP/batch-args.out" 2> "$TMP/batch-args.err"
ARGS_BATCH_RC=$?
set -e
for result in "$LATE_BATCH_RC" "$BATCH65_RC" "$CORRUPT_BATCH_RC" \
  "$EMPTY_BATCH_RC" "$MISSING_BATCH_RC" "$LISP_BATCH_RC"; do
  test "$result" -eq 2 || { echo "помилковий статус startup-пакета=$result" >&2; exit 1; }
done
test "$ARGS_BATCH_RC" -eq 64
for item in batch-late batch65 batch-corrupt batch-empty batch-missing batch-lisp batch-args; do
  test ! -s "$TMP/$item.out" || { echo "частковий stdout: $item" >&2; exit 1; }
done
grep -Fq 'пакетна форма=3' "$TMP/batch-late.err"
grep -Fq '1..64' "$TMP/batch65.err"
grep -Fq 'фізичного .sens' "$TMP/batch-lisp.err"
grep -q '0 unfreed memory blocks' "$TMP/batch-late.err"
grep -q '0 unfreed memory blocks' "$TMP/batch65.err"
echo 'CORE4-СТАРТОВИЙ-ПАКЕТ-ГАРАЗД форми=3,64 відхилення=65 пізня-помилка=3 stdout=атомарно stdin=продовжено'


# G5.20: справжній фізичний пакет у вже запущеному stdin-сеансі,
# не повторний startup та не текстове виконання української .lisp.
{
  printf '%s\n' "$TMP/01-tak.sens"
  printf ':пакет %s\r\n' "$TMP/paket3.sens"
  printf ':пакет %s\n' "$TMP/paket-pomylka.sens"
  printf '%s\r\n' "$TMP/03-ni.sens"
  printf ':пакет %s\n' "$TMP/paket64.sens"
  printf ':пакет %s\n' "$TMP/paket65.sens"
  printf ':пакет %s\n' "$TMP/paket-nekorektne.sens"
  printf ':пакет\n'
  printf ':пакет %s\n' "$TMP/missing.sens"
  printf ':пакет %s\n' "$ROOT/external/sens/lib/core4.lisp"
  printf '%s\n' "$TMP/09-povtornyi.sens" ':вихід'
} > "$TMP/live-batch.in"
set +e
"$BIN" --сеанс "$ROOT" < "$TMP/live-batch.in" \
  > "$TMP/live-batch.out" 2> "$TMP/live-batch.err"
LIVE_RC=$?
set -e
test "$LIVE_RC" -eq 2 || {
  echo "неочікуваний статус виконуваного live-пакета: $LIVE_RC" >&2; exit 1;
}
cat > "$TMP/live-batch.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000000
РЕЗУЛЬТАТ 6 1:0
EOF
for ((i=7;i<=70;i++)); do
  printf 'РЕЗУЛЬТАТ %d 1:1\n' "$i" >> "$TMP/live-batch.expected"
done
printf 'РЕЗУЛЬТАТ 76 1:1\n' >> "$TMP/live-batch.expected"
diff -u "$TMP/live-batch.expected" "$TMP/live-batch.out"
test "$(grep -c '^ПОМИЛКА ' "$TMP/live-batch.err")" -eq 6
for n in 5 71 72 73 74 75; do
  grep -q "^ПОМИЛКА $n " "$TMP/live-batch.err"
  ! grep -q "^РЕЗУЛЬТАТ $n " "$TMP/live-batch.out"
done
grep -q 'пакетна форма=3' "$TMP/live-batch.err"
grep -q '1..64' "$TMP/live-batch.err"
grep -q 'потребує фізичний шлях' "$TMP/live-batch.err"
grep -q 'фізичного .sens' "$TMP/live-batch.err"
grep -q '0 unfreed memory blocks' "$TMP/live-batch.err"

# Стартовий пакет і нова команда використовують той самий екземпляр Runtime.
{
  printf ':пакет %s\n' "$TMP/paket3.sens"
  printf '%s\n' "$TMP/03-ni.sens" ':вихід'
} > "$TMP/startup-live.in"
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --завантажити-пакет "$TMP/paket3.sens" < "$TMP/startup-live.in" \
  > "$TMP/startup-live.out" 2> "$TMP/startup-live.err"
cat > "$TMP/startup-live.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000000
РЕЗУЛЬТАТ 5 1:1
РЕЗУЛЬТАТ 6 1:0
РЕЗУЛЬТАТ 7 24:000000000000000000000000
РЕЗУЛЬТАТ 8 1:0
EOF
diff -u "$TMP/startup-live.expected" "$TMP/startup-live.out"
! grep -q '^ПОМИЛКА ' "$TMP/startup-live.err"
grep -q '0 unfreed memory blocks' "$TMP/startup-live.err"
echo 'CORE4-ЖИВИЙ-ПАКЕТ-ГАРАЗД форми=3,64 негативних=6 відновлення=так stdin+startup=одне-середовище'

# G5.21: знімок ТІЛЬКИ виконаних початкових фізичних відповідей.
# Не відновлюємо біти з тексту "ширина:біти"; очікування окремо пакує
# TExactWords чинним T5M кодеком.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4session-capture "$ROOT/scripts/test-core4session-capture.pas"
"$ROOT/build/m0.2/bin/test-core4session-capture" "$TMP/expected-capture.sens"
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --завантажити-пакет "$TMP/paket3.sens" \
  --завантажити "$TMP/03-ni.sens" \
  --зберегти-початкові "$TMP/capture.sens" \
  <"$TMP/batch-session.in" >"$TMP/capture.out" 2>"$TMP/capture.err"
cmp "$TMP/expected-capture.sens" "$TMP/capture.sens"
diff -u "$TMP/batch-session.expected" "$TMP/capture.out"
grep -q '0 unfreed memory blocks' "$TMP/capture.err"

# Один негативний останній виклик скасовує ВСІ фізичні виходи й
# увесь startup stdout (навіть після вже обчисленого D1:1).
set +e
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --завантажити-пакет "$TMP/paket-pomylka.sens" \
  --зберегти-початкові "$TMP/not-created.sens" \
  <"$TMP/batch-session.in" >"$TMP/capture-late.out" 2>"$TMP/capture-late.err"
LATE_CAPTURE_RC=$?
# Наявні дані не перезаписуються, навіть якщо всі форми успішні.
cp "$TMP/expected-capture.sens" "$TMP/occupied.sens"
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --зберегти-початкові "$TMP/occupied.sens" \
  <"$TMP/batch-session.in" >"$TMP/capture-occupied.out" 2>"$TMP/capture-occupied.err"
OCCUPIED_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --зберегти-початкові "$TMP/rejected.lisp" \
  <"$TMP/batch-session.in" >"$TMP/capture-lisp.out" 2>"$TMP/capture-lisp.err"
LISP_CAPTURE_RC=$?
"$BIN" --сеанс "$ROOT" \
  --зберегти-початкові "$TMP/no-startup.sens" \
  <"$TMP/batch-session.in" >"$TMP/capture-no-start.out" 2>"$TMP/capture-no-start.err"
NO_START_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --зберегти-початкові "$TMP/dup1.sens" \
  --зберегти-початкові "$TMP/dup2.sens" \
  <"$TMP/batch-session.in" >"$TMP/capture-dup.out" 2>"$TMP/capture-dup.err"
DUP_RC=$?
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  --зберегти-початкові "$TMP/bad-dir/output.sens" \
  <"$TMP/batch-session.in" >"$TMP/capture-dir.out" 2>"$TMP/capture-dir.err"
DIR_RC=$?
set -e
test "$LATE_CAPTURE_RC" -eq 2 && test "$OCCUPIED_RC" -eq 2 &&
  test "$LISP_CAPTURE_RC" -eq 64 && test "$NO_START_RC" -eq 64 &&
  test "$DUP_RC" -eq 64 && test "$DIR_RC" -eq 2
for name in late occupied lisp no-start dup dir; do
  test ! -s "$TMP/capture-$name.out"
done
test ! -e "$TMP/not-created.sens" &&
  test ! -e "$TMP/rejected.lisp" &&
  test ! -e "$TMP/no-startup.sens" &&
  test ! -e "$TMP/dup1.sens" &&
  test ! -e "$TMP/dup2.sens"
cmp "$TMP/expected-capture.sens" "$TMP/occupied.sens"
grep -Fq 'пакетна форма=3' "$TMP/capture-late.err"
grep -Fq 'уже існує' "$TMP/capture-occupied.err"
grep -q '0 unfreed memory blocks' "$TMP/capture-late.err"
echo 'CORE4-ЗНІМОК-ВІДПОВІДЕЙ-ГАРАЗД фізичні-слова=5 T5M=точні-байти перезапис=ні частковий-файл=ні'


# G5.22: явна українська `укр` поверхня у ВЖЕ ПРАЦЮЮЧОМУ Core4 runtime.
# Перетворювач не виконує SENS, а створює byte-exact T5M із pinned D1–D9.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4-uk-session "$ROOT/scripts/test-core4-uk-session.pas"
"$ROOT/build/m0.2/bin/test-core4-uk-session" "$ROOT" "$TMP"

# Межа файлу раніше від parser/binder, а не обрізка UTF-8.
head -c 1048577 /dev/zero > "$TMP/oversize.lisp"
{
  printf '%s\n' "$TMP/01-tak.sens"
  printf ':укр %s\r\n' "$TMP/01-tak.lisp"
  printf ':укр %s\n' "$TMP/03-ni.lisp"
  printf ':укр %s\n' "$TMP/multi.lisp"
  printf ':укр %s\n' "$TMP/невідома.lisp"
  printf ':укр %s\n' "$TMP/04-d24-argument.sens"
  printf ':укр\n'
  printf ':укр %s\n' "$TMP/missing.lisp"
  printf ':укр %s\n' "$TMP/oversize.lisp"
  printf ':пакет %s\n' "$TMP/paket3.sens"
  printf ':укр %s\n' "$TMP/01-tak.lisp"
  printf '%s\n' ':вихід'
} > "$TMP/ukr-live.in"
set +e
"$BIN" --сеанс "$ROOT" < "$TMP/ukr-live.in" \
  > "$TMP/ukr-live.out" 2> "$TMP/ukr-live.err"
UKR_RC=$?
set -e
test "$UKR_RC" -eq 2 || { echo "очікувався код 2 українських відмов; отримано $UKR_RC" >&2; exit 1; }
cat > "$TMP/ukr-live.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 10 1:1
РЕЗУЛЬТАТ 11 1:0
РЕЗУЛЬТАТ 12 24:000000000000000000000000
РЕЗУЛЬТАТ 13 1:1
EOF
diff -u "$TMP/ukr-live.expected" "$TMP/ukr-live.out"
test "$(grep -c '^ПОМИЛКА ' "$TMP/ukr-live.err")" -eq 6
for n in 4 5 6 7 8 9; do
  grep -q "^ПОМИЛКА $n " "$TMP/ukr-live.err"
  ! grep -q "^РЕЗУЛЬТАТ $n " "$TMP/ukr-live.out"
done
grep '^ПОМИЛКА 6 ' "$TMP/ukr-live.err" | grep -Fq 'файл .lisp'
grep '^ПОМИЛКА 7 ' "$TMP/ukr-live.err" | grep -Fq 'файл .lisp'
grep '^ПОМИЛКА 9 ' "$TMP/ukr-live.err" | grep -Fq '1 MiB'
grep -q '0 unfreed memory blocks' "$TMP/ukr-live.err"

# Звичайний startup `.sens` і український ввід працюють на одному
# завантаженому з pinned core4.sens TCore4Runtime, не на echo-loop.
{
  printf ':укр %s\n' "$TMP/03-ni.lisp"
  printf ':укр %s\n' "$TMP/01-tak.lisp"
  printf '%s\n' ':вихід'
} > "$TMP/ukr-startup.in"
"$BIN" --сеанс "$ROOT" --завантажити "$TMP/01-tak.sens" \
  < "$TMP/ukr-startup.in" > "$TMP/ukr-startup.out" \
  2> "$TMP/ukr-startup.err"
cat > "$TMP/ukr-startup.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:0
РЕЗУЛЬТАТ 3 1:1
EOF
diff -u "$TMP/ukr-startup.expected" "$TMP/ukr-startup.out"
! grep -q '^ПОМИЛКА ' "$TMP/ukr-startup.err"
grep -q '0 unfreed memory blocks' "$TMP/ukr-startup.err"
echo 'CORE4-УКР-СЕАНС-ГАРАЗД D7+D1=фізично-виконано українська-укр=.lisp негативних=6 D12+=не-вгадано'


# G5.24: багато українських укр-форм в одному постійному Core4 runtime.
# Друга/третя форма може бути фізично оборотною, але семантично
# недопустимою: тоді ВСЯ відповідь host-пакета залишається невидимою.
{
  printf '%s\n' "$TMP/01-tak.sens"
  printf ':укр-пакет %s\r\n' "$TMP/ukr-paket2.lisp"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket-late.lisp"
  printf ':укр %s\n' "$TMP/03-ni.lisp"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket3.lisp"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket65.lisp"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket-invalid.lisp"
  printf ':укр-пакет\n'
  printf ':укр-пакет %s\n' "$TMP/missing.lisp"
  printf ':укр-пакет %s\n' "$TMP/01-tak.sens"
  printf ':укр-пакет %s\n' "$TMP/oversize.lisp"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket64.lisp"
  printf ':укр %s\n' "$TMP/01-tak.lisp"
  printf '%s\n' ':вихід'
} > "$TMP/ukr-batch-live.in"
set +e
"$BIN" --сеанс "$ROOT" < "$TMP/ukr-batch-live.in" \
  > "$TMP/ukr-batch-live.out" 2> "$TMP/ukr-batch-live.err"
UKR_BATCH_RC=$?
set -e
test "$UKR_BATCH_RC" -eq 2 || {
  echo "Неправильний статус українських пакетів: $UKR_BATCH_RC" >&2
  exit 1
}
cat > "$TMP/ukr-batch-live.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 5 1:0
РЕЗУЛЬТАТ 6 1:1
РЕЗУЛЬТАТ 7 1:0
РЕЗУЛЬТАТ 8 1:1
EOF
for ((i=15;i<=78;i++)); do
  printf 'РЕЗУЛЬТАТ %d 1:1\n' "$i" >> "$TMP/ukr-batch-live.expected"
done
printf 'РЕЗУЛЬТАТ 79 1:1\n' >> "$TMP/ukr-batch-live.expected"
diff -u "$TMP/ukr-batch-live.expected" "$TMP/ukr-batch-live.out"
test "$(grep -c '^ПОМИЛКА ' "$TMP/ukr-batch-live.err")" -eq 7
for n in 4 9 10 11 12 13 14; do
  grep -q "^ПОМИЛКА $n " "$TMP/ukr-batch-live.err"
  ! grep -q "^РЕЗУЛЬТАТ $n " "$TMP/ukr-batch-live.out"
done
grep '^ПОМИЛКА 4 ' "$TMP/ukr-batch-live.err" | grep -Fq 'пакетна форма=3'
grep '^ПОМИЛКА 4 ' "$TMP/ukr-batch-live.err" | grep -Fq 'D7-замиканням'
grep '^ПОМИЛКА 9 ' "$TMP/ukr-batch-live.err" | grep -Fq '1..64'
grep '^ПОМИЛКА 11 ' "$TMP/ukr-batch-live.err" | grep -Fq 'файл .lisp'
grep '^ПОМИЛКА 13 ' "$TMP/ukr-batch-live.err" | grep -Fq 'файл .lisp'
grep '^ПОМИЛКА 14 ' "$TMP/ukr-batch-live.err" | grep -Fq '1 MiB'
grep -q '0 unfreed memory blocks' "$TMP/ukr-batch-live.err"

# Перевіряємо спільність startup, українського пакета і звичайного
# точного українського виконання у ТОМУ САМОМУ pinned runtime.
{
  printf ':укр-пакет %s\n' "$TMP/ukr-paket2.lisp"
  printf ':укр %s\n' "$TMP/01-tak.lisp"
  printf '%s\n' ':вихід'
} > "$TMP/ukr-batch-startup.in"
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --завантажити-пакет "$TMP/paket3.sens" \
  < "$TMP/ukr-batch-startup.in" > "$TMP/ukr-batch-startup.out" \
  2> "$TMP/ukr-batch-startup.err"
cat > "$TMP/ukr-batch-startup.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000000
РЕЗУЛЬТАТ 5 1:1
РЕЗУЛЬТАТ 6 1:0
РЕЗУЛЬТАТ 7 1:1
EOF
diff -u "$TMP/ukr-batch-startup.expected" "$TMP/ukr-batch-startup.out"
! grep -q '^ПОМИЛКА ' "$TMP/ukr-batch-startup.err"
grep -q '0 unfreed memory blocks' "$TMP/ukr-batch-startup.err"
echo 'CORE4-УКР-ПАКЕТ-ГАРАЗД фізичних-форм=2,3,64,65 пізня-відмова=3 негативних=7 відновлення=так'


# G5.25: явні українські укр-проєкції при запуску, НЕ імпліцитний
# виконуваний .lisp. Усі startup відповіді фізично виконуються до
# першого stdout і до створення канонічного архіву T5M.
printf ':укр %s\n' "$TMP/01-tak.lisp" >"$TMP/ukr-boot.in"
printf '%s\n' ':вихід' >>"$TMP/ukr-boot.in"
"$BIN" --сеанс "$ROOT" \
  --завантажити "$TMP/01-tak.sens" \
  --завантажити-укр-пакет "$TMP/ukr-paket2.lisp" \
  --завантажити "$TMP/05-global-d24-0.sens" \
  --завантажити-укр "$TMP/03-ni.lisp" \
  --зберегти-початкові "$TMP/ukr-boot-physical.sens" \
  <"$TMP/ukr-boot.in" >"$TMP/ukr-boot.out" 2>"$TMP/ukr-boot.err"
cat >"$TMP/ukr-boot.expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000000
РЕЗУЛЬТАТ 5 1:0
РЕЗУЛЬТАТ 6 1:1
EOF
diff -u "$TMP/ukr-boot.expected" "$TMP/ukr-boot.out"
cmp "$TMP/expected-capture.sens" "$TMP/ukr-boot-physical.sens"
! grep -q '^ПОМИЛКА ' "$TMP/ukr-boot.err"
grep -q '0 unfreed memory blocks' "$TMP/ukr-boot.err"

# 64 форми української проєкції реально проходять той самий runtime;
# наступні startup і stdin відповіді мають зберегти точні номери.
printf '%s\n' "$TMP/03-ni.sens" ':вихід' >"$TMP/ukr-boot64.in"
"$BIN" --сеанс "$ROOT" \
  --завантажити-укр-пакет "$TMP/ukr-paket64.lisp" \
  --завантажити-укр "$TMP/01-tak.lisp" \
  <"$TMP/ukr-boot64.in" >"$TMP/ukr-boot64.out" 2>"$TMP/ukr-boot64.err"
: >"$TMP/ukr-boot64.expected"
for ((i=1;i<=65;i++)); do
  printf 'РЕЗУЛЬТАТ %d 1:1\n' "$i" >>"$TMP/ukr-boot64.expected"
done
printf 'РЕЗУЛЬТАТ 66 1:0\n' >>"$TMP/ukr-boot64.expected"
diff -u "$TMP/ukr-boot64.expected" "$TMP/ukr-boot64.out"
grep -q '0 unfreed memory blocks' "$TMP/ukr-boot64.err"

# Кожен негатив додається ПІСЛЯ успішного фізичного startup;
# навіть якщо два попередні визначення дали результат, невдалий
# український пакет не публікує ні часткового stdout, ні .sens.
reject_ukr_boot() {
  local label=$1
  shift
  local output="$TMP/ukr-boot-rejected-$label.sens"
  local rc
  set +e
  "$BIN" --сеанс "$ROOT" \
    --завантажити "$TMP/01-tak.sens" \
    "$@" --зберегти-початкові "$output" \
    <"$TMP/ukr-boot.in" >"$TMP/ukr-boot-$label.out" \
    2>"$TMP/ukr-boot-$label.err"
  rc=$?
  set -e
  if [ "$rc" -ne 2 ]; then
    echo "УКР-СТАРТ-ПОМИЛКА: $label код=$rc замість 2" >&2
    exit 1
  fi
  test ! -s "$TMP/ukr-boot-$label.out"
  test ! -e "$output"
  grep -Fq 'ПОМИЛКА ЗАВАНТАЖЕННЯ CORE4' "$TMP/ukr-boot-$label.err"
  grep -q '0 unfreed memory blocks' "$TMP/ukr-boot-$label.err"
}
reject_ukr_boot late \
  --завантажити-укр-пакет "$TMP/ukr-paket-late.lisp"
grep -Fq 'пакетна форма=3' "$TMP/ukr-boot-late.err"
reject_ukr_boot multi-single \
  --завантажити-укр "$TMP/ukr-paket2.lisp"
reject_ukr_boot 65 \
  --завантажити-укр-пакет "$TMP/ukr-paket65.lisp"
grep -Fq '1..64' "$TMP/ukr-boot-65.err"
reject_ukr_boot unknown \
  --завантажити-укр "$TMP/невідома.lisp"
reject_ukr_boot invalid-batch \
  --завантажити-укр-пакет "$TMP/ukr-paket-invalid.lisp"
reject_ukr_boot missing \
  --завантажити-укр "$TMP/немає.lisp"
reject_ukr_boot wrong-extension \
  --завантажити-укр "$TMP/01-tak.sens"
grep -Fq 'файл .lisp' "$TMP/ukr-boot-wrong-extension.err"
reject_ukr_boot too-large \
  --завантажити-укр-пакет "$TMP/oversize.lisp"
grep -Fq '1 MiB' "$TMP/ukr-boot-too-large.err"
reject_ukr_boot empty \
  --завантажити-укр "$TMP/порожня.lisp"
reject_ukr_boot numeric-text \
  --завантажити-укр "$TMP/число.lisp"
echo 'CORE4-УКР-СТАРТ-ГАРАЗД фізичних-відповідей=5 архів=T5M-байт-у-байт форми=64 негативних=10 атомарний-startup=так'


# G5.27: запам'ятовуються тільки виконані stdin відповіді.
# Джерело для expected є незалежним від stdout: власний T5M Encode
# над відповідями існуючих pinned D7/D1/D24 фізичних свідків.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4session-live-capture "$ROOT/scripts/test-core4session-live-capture.pas"
"$ROOT/build/m0.2/bin/test-core4session-live-capture" "$TMP"

{
  printf ':зберегти-останнє %s\n' "$TMP/порожня-історія.sens"
  printf '%s\n' "$TMP/01-tak.sens"
  printf ':зберегти-останнє %s\n' "$TMP/остання-фізична.sens"
  printf ':зберегти-останнє %s\n' "$TMP/остання-фізична-копія.sens"
  printf ':укр %s\n' "$TMP/03-ni.lisp"
  printf ':зберегти-останнє %s\n' "$TMP/остання-укр.sens"
  printf ':пакет %s\n' "$TMP/paket3.sens"
  printf ':зберегти-останнє %s\n' "$TMP/остання-пакет3.sens"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket2.lisp"
  printf ':зберегти-останнє %s\n' "$TMP/остання-укр2.sens"
  printf ':пакет %s\n' "$TMP/paket64.sens"
  printf ':зберегти-останнє %s\n' "$TMP/остання-пакет64.sens"
  printf '%s\n' ':вихід'
} > "$TMP/live-last.in"
set +e
"$BIN" --сеанс "$ROOT" <"$TMP/live-last.in" \
  >"$TMP/live-last.out" 2>"$TMP/live-last.err"
LIVE_LAST_RC=$?
set -e
test "$LIVE_LAST_RC" -eq 2
grep -q '^ПОМИЛКА 1 ' "$TMP/live-last.err"
grep -q 'немає останніх успішних' "$TMP/live-last.err"
test ! -e "$TMP/порожня-історія.sens"
cmp "$TMP/останній-так-очікування.sens" "$TMP/остання-фізична.sens"
cmp "$TMP/останній-так-очікування.sens" "$TMP/остання-фізична-копія.sens"
cmp "$TMP/останній-ні-очікування.sens" "$TMP/остання-укр.sens"
cmp "$TMP/останній-пакет3-очікування.sens" "$TMP/остання-пакет3.sens"
cmp "$TMP/останній-укр2-очікування.sens" "$TMP/остання-укр2.sens"
cmp "$TMP/останній-пакет64-очікування.sens" "$TMP/остання-пакет64.sens"
test "$(grep -c '^ПОМИЛКА ' "$TMP/live-last.err")" -eq 1
grep -q '0 unfreed memory blocks' "$TMP/live-last.err"
# Ніяких удаваних рядків РЕЗУЛЬТАТ від самих команд збереження.
test "$(grep -c '^РЕЗУЛЬТАТ ' "$TMP/live-last.out")" -eq 71

# Пізня відмова при реально допустимому T5M пакеті скасовує cache.
# Потім невдале збереження (існуючий output / хибне розширення /
# відсутня директорія) не залишає старий результат доступним.
cp "$TMP/останній-так-очікування.sens" "$TMP/вже-існує.sens"
{
  printf ':пакет %s\n' "$TMP/paket3.sens"
  printf ':пакет %s\n' "$TMP/paket-pomylka.sens"
  printf ':зберегти-останнє %s\n' "$TMP/старе-після-відмови.sens"
  printf ':укр %s\n' "$TMP/01-tak.lisp"
  printf ':зберегти-останнє %s\n' "$TMP/вже-існує.sens"
  printf ':зберегти-останнє %s\n' "$TMP/старе-після-перезапису.sens"
  printf '%s\n' "$TMP/03-ni.sens"
  printf ':зберегти-останнє %s\n' "$TMP/не-фізичний.lisp"
  printf ':зберегти-останнє %s\n' "$TMP/старе-після-розширення.sens"
  printf ':укр-пакет %s\n' "$TMP/ukr-paket2.lisp"
  printf ':зберегти-останнє %s\n' "$TMP/немає-директорії/відповідь.sens"
  printf ':зберегти-останнє %s\n' "$TMP/старе-після-каталогу.sens"
  printf '%s\n' ':зберегти-останнє'
  printf ':укр %s\n' "$TMP/01-tak.lisp"
  printf ':зберегти-останнє %s\n' "$TMP/нова-після-відмов.sens"
  printf '%s\n' ':вихід'
} > "$TMP/live-last-negative.in"
set +e
"$BIN" --сеанс "$ROOT" <"$TMP/live-last-negative.in" \
  >"$TMP/live-last-negative.out" 2>"$TMP/live-last-negative.err"
LIVE_LAST_NEG_RC=$?
set -e
test "$LIVE_LAST_NEG_RC" -eq 2
test "$(grep -c '^ПОМИЛКА ' "$TMP/live-last-negative.err")" -eq 9
# Нумерація містить усі УСПІШНІ результати: пакет3 займає 1..3,
# наступний пакет2 займає 12..13; host-збереження теж займає номер.
for n in 4 5 7 8 10 11 14 15 16; do
  grep -q "^ПОМИЛКА $n " "$TMP/live-last-negative.err"
done
grep -Fq 'пакетна форма=3' "$TMP/live-last-negative.err"
grep -Fq 'уже існує' "$TMP/live-last-negative.err"
grep -Fq 'вихід має бути новим фізичним файлом .sens' "$TMP/live-last-negative.err"
cmp "$TMP/останній-так-очікування.sens" "$TMP/вже-існує.sens"
cmp "$TMP/останній-так-очікування.sens" "$TMP/нова-після-відмов.sens"
for name in \
  старе-після-відмови старе-після-перезапису \
  старе-після-розширення старе-після-каталогу
do
  test ! -e "$TMP/$name.sens"
done
test ! -e "$TMP/не-фізичний.lisp"
grep -q '0 unfreed memory blocks' "$TMP/live-last-negative.err"
echo 'CORE4-ОСТАННЯ-ВІДПОВІДЬ-ГАРАЗД фізичних=1,2,3,64 атомарне-збереження=так stale=ні overwrite=ні recovery=так'


# G5.29: дійсний inline український ввод ОДНІЄЇ форми без .lisp файла.
# Канонічні приклади створені ВЖЕ з pinned physical D7+D1 в тестовому
# генераторі G5.22 через PhysicalToUkrainian, не прописані вручну.
TAK_INLINE="$(cat "$TMP/01-tak.lisp")"
NI_INLINE="$(cat "$TMP/03-ni.lisp")"
BAD_D4_INLINE="$(tail -n 1 "$TMP/ukr-paket-late.lisp")"
test -n "$TAK_INLINE" && test -n "$NI_INLINE" && test -n "$BAD_D4_INLINE"
{
  printf '%s\n' ':укр-рядок'
  printf ':укр-рядок %s\n' "$TAK_INLINE"
  printf ':зберегти-останнє %s\n' "$TMP/inline-tak-result.sens"
  printf ':укр-рядок %s\r\n' "$NI_INLINE"
  printf '%s\n' ':укр-рядок 24'
  printf ':зберегти-останнє %s\n' "$TMP/inline-stale-after-d12.sens"
  printf ':укр-рядок %s %s\n' "$TAK_INLINE" "$NI_INLINE"
  printf '%s\n' ':укр-рядок невідоме'
  printf ':укр-рядок %s\n' "$BAD_D4_INLINE"
  printf '%s\n' "$TMP/03-ni.sens"
  printf ':укр-рядок %s\n' "$TAK_INLINE"
  printf ':зберегти-останнє %s\n' "$TMP/inline-recovery-result.sens"
  printf '%s' ':укр-рядок '
  head -c 4200 /dev/zero | tr '\000' 'x'
  printf '\n'
  printf ':зберегти-останнє %s\n' "$TMP/inline-stale-after-bound.sens"
  printf ':укр-рядок %s\n' "$NI_INLINE"
  printf '%s\n' ':вихід'
} >"$TMP/inline-d7.in"
set +e
"$BIN" --сеанс "$ROOT" <"$TMP/inline-d7.in" \
  >"$TMP/inline-d7.out" 2>"$TMP/inline-d7.err"
INLINE_D7_RC=$?
set -e
test "$INLINE_D7_RC" -eq 2 || {
  echo "Невірний статус українського inline D7: $INLINE_D7_RC" >&2
  exit 1
}
cat >"$TMP/inline-d7.expected" <<'EOF'
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 4 1:0
РЕЗУЛЬТАТ 10 1:0
РЕЗУЛЬТАТ 11 1:1
РЕЗУЛЬТАТ 15 1:0
EOF
diff -u "$TMP/inline-d7.expected" "$TMP/inline-d7.out"
cmp "$TMP/останній-так-очікування.sens" "$TMP/inline-tak-result.sens"
cmp "$TMP/останній-так-очікування.sens" "$TMP/inline-recovery-result.sens"
test ! -e "$TMP/inline-stale-after-d12.sens"
test ! -e "$TMP/inline-stale-after-bound.sens"
test "$(grep -c '^ПОМИЛКА ' "$TMP/inline-d7.err")" -eq 8
for n in 1 5 6 7 8 9 13 14; do
  grep -q "^ПОМИЛКА $n " "$TMP/inline-d7.err"
  ! grep -q "^РЕЗУЛЬТАТ $n " "$TMP/inline-d7.out"
done
grep '^ПОМИЛКА 1 ' "$TMP/inline-d7.err" | grep -Fq 'одну українську форму'
grep '^ПОМИЛКА 9 ' "$TMP/inline-d7.err" | grep -Fq 'D7-замиканням'
grep '^ПОМИЛКА 13 ' "$TMP/inline-d7.err" | grep -Fq 'межа=4096'
grep -q '0 unfreed memory blocks' "$TMP/inline-d7.err"
echo 'CORE4-УКР-РЯДОК-ГАРАЗД pinned-D7+точний-D1 real-runtime=так D12+=відхилено форми=одна межа=4096 physical-archive=byte-exact відновлення=так'


# G5.31: один stdin-рядок несе 1..64 окремі звичайні українські
# «укр» форми, але лише явна :укр-рядки дозволяє пакет.
# TAK_INLINE, NI_INLINE і BAD_D4_INLINE походять тільки з pinned
# PhysicalToUkrainian реальних T5M fixtures G5.22/G5.29.
INLINE_BATCH64="$TAK_INLINE"
for ((i=2;i<=64;i++)); do INLINE_BATCH64+=" $TAK_INLINE"; done
INLINE_BATCH65="$INLINE_BATCH64 $TAK_INLINE"
INLINE_BATCH65_BYTES=$(printf '%s' ":укр-рядки $INLINE_BATCH65" | LC_ALL=C wc -c)
test "$INLINE_BATCH65_BYTES" -le 4096 || {
  echo "G5.31-БЛОКЕР: 65 pinned укр-форм >4096 UTF-8 host bytes" >&2
  exit 1
}

{
  printf ':укр-рядки %s %s %s\n' "$TAK_INLINE" "$NI_INLINE" "$TAK_INLINE"
  printf ':зберегти-останнє %s\n' "$TMP/ukr-inline-batch3.sens"
  printf ':укр-рядки %s %s\r\n' "$TAK_INLINE" "$NI_INLINE"
  printf ':зберегти-останнє %s\n' "$TMP/ukr-inline-batch2.sens"
  printf ':укр-рядки %s\n' "$INLINE_BATCH64"
  printf ':зберегти-останнє %s\n' "$TMP/ukr-inline-batch64.sens"
  printf ':укр-рядок %s\n' "$NI_INLINE"
  printf '%s\n' ':вихід'
} >"$TMP/ukr-inline-batch-ok.in"
"$BIN" --сеанс "$ROOT" <"$TMP/ukr-inline-batch-ok.in" \
  >"$TMP/ukr-inline-batch-ok.out" 2>"$TMP/ukr-inline-batch-ok.err"
{
  printf 'РЕЗУЛЬТАТ 1 1:1\n'
  printf 'РЕЗУЛЬТАТ 2 1:0\n'
  printf 'РЕЗУЛЬТАТ 3 1:1\n'
  printf 'РЕЗУЛЬТАТ 5 1:1\n'
  printf 'РЕЗУЛЬТАТ 6 1:0\n'
  for ((i=8;i<=71;i++)); do
    printf 'РЕЗУЛЬТАТ %d 1:1\n' "$i"
  done
  printf 'РЕЗУЛЬТАТ 73 1:0\n'
} >"$TMP/ukr-inline-batch-ok.expected"
diff -u "$TMP/ukr-inline-batch-ok.expected" "$TMP/ukr-inline-batch-ok.out"
# Два незалежні фізичні T5M expectations, утворені до сеансу.
cmp "$TMP/останній-укр2-очікування.sens" "$TMP/ukr-inline-batch2.sens"
cmp "$TMP/останній-пакет64-очікування.sens" "$TMP/ukr-inline-batch64.sens"
test -s "$TMP/ukr-inline-batch3.sens"
! grep -q '^ПОМИЛКА ' "$TMP/ukr-inline-batch-ok.err"
grep -q '0 unfreed memory blocks' "$TMP/ukr-inline-batch-ok.err"

{
  printf '%s\n' ':укр-рядки'
  printf '%s\n' ':укр-рядки '
  printf ':укр-рядки %s %s %s\n' "$TAK_INLINE" "$NI_INLINE" "$BAD_D4_INLINE"
  printf ':зберегти-останнє %s\n' "$TMP/ukr-inline-stale-after-d4.sens"
  printf ':укр-рядки %s 24\n' "$TAK_INLINE"
  printf ':укр-рядки %s невідоме\n' "$TAK_INLINE"
  printf ':укр-рядки %s\n' "$INLINE_BATCH65"
  printf '%s' ':укр-рядки '
  head -c 4200 /dev/zero | tr '\000' 'x'
  printf '\n'
  printf ':зберегти-останнє %s\n' "$TMP/ukr-inline-stale-after-overflow.sens"
  printf ':укр-рядки %s\n' "$NI_INLINE"
  printf ':зберегти-останнє %s\n' "$TMP/ukr-inline-recovered.sens"
  printf ':укр-рядок %s %s\n' "$TAK_INLINE" "$NI_INLINE"
  printf ':укр-рядки %s\n' "$TAK_INLINE"
  printf '%s\n' ':вихід'
} >"$TMP/ukr-inline-batch-bad.in"
set +e
"$BIN" --сеанс "$ROOT" <"$TMP/ukr-inline-batch-bad.in" \
  >"$TMP/ukr-inline-batch-bad.out" 2>"$TMP/ukr-inline-batch-bad.err"
INLINE_BATCH_BAD_RC=$?
set -e
test "$INLINE_BATCH_BAD_RC" -eq 2 || {
  echo "G5.31: помилковий статус пакета $INLINE_BATCH_BAD_RC" >&2
  exit 1
}
cat >"$TMP/ukr-inline-batch-bad.expected" <<'EOF'
РЕЗУЛЬТАТ 10 1:0
РЕЗУЛЬТАТ 13 1:1
EOF
diff -u "$TMP/ukr-inline-batch-bad.expected" "$TMP/ukr-inline-batch-bad.out"
cmp "$TMP/останній-ні-очікування.sens" "$TMP/ukr-inline-recovered.sens"
test ! -e "$TMP/ukr-inline-stale-after-d4.sens"
test ! -e "$TMP/ukr-inline-stale-after-overflow.sens"
test "$(grep -c '^ПОМИЛКА ' "$TMP/ukr-inline-batch-bad.err")" -eq 10
for n in 1 2 3 4 5 6 7 8 9 12; do
  grep -q "^ПОМИЛКА $n " "$TMP/ukr-inline-batch-bad.err"
  ! grep -q "^РЕЗУЛЬТАТ $n " "$TMP/ukr-inline-batch-bad.out"
done
grep '^ПОМИЛКА 3 ' "$TMP/ukr-inline-batch-bad.err" | grep -Fq 'пакетна форма=3'
grep '^ПОМИЛКА 7 ' "$TMP/ukr-inline-batch-bad.err" | grep -Fq '1..64'
grep '^ПОМИЛКА 8 ' "$TMP/ukr-inline-batch-bad.err" | grep -Fq 'межа=4096'
grep -q '0 unfreed memory blocks' "$TMP/ukr-inline-batch-bad.err"
echo 'CORE4-УКР-РЯДКИ-ГАРАЗД pinned-D7+D1=так batch=2,3,64 reject=65+10-error stdout=атомарно exact-T5M=так recovery=так'


# G5.55 — ТРИ фізичні результати одного постійного pinned Core4 runtime.
# Свідки створює ВЖЕ НАЯВНИЙ FPC генератор (перші 3 pinned Core4
# DEFINE): справжній D7-виклик, D4:1110 складений список, D24 opaque.
# Не синтезуємо мовного закону та не конвертуємо .lisp неявно.
mkdir -p "$TMP/складені"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4-session-mixed-fixtures "$ROOT/scripts/test-core4multiroot.pas"
"$ROOT/build/m0.2/bin/test-core4-session-mixed-fixtures" \
  "$ROOT" "$TMP/складені" >"$TMP/складені/генератор.out" 2>"$TMP/складені/генератор.err"
grep -Fq 'CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД' "$TMP/складені/генератор.out"
grep -Fq '0 unfreed memory blocks' "$TMP/складені/генератор.err"
{
  printf '%s\n' ':корені'
  printf ':корені %s\n' "$TMP/складені/good.sens"
  printf ':зберегти-останнє %s\n' "$TMP/складені/збережено.sens"
  printf '%s\n' "$TMP/01-tak.sens"
  printf ':корені %s\n' "$TMP/складені/late.sens"
  printf ':зберегти-останнє %s\n' "$TMP/складені/старе.sens"
  printf ':корені %s\n' "$TMP/складені/too-many.sens"
  printf ':корені %s\n' "$TMP/складені/broken.sens"
  printf ':корені %s\n' "$TMP/складені/good.sens"
  printf ':зберегти-останнє %s\n' "$TMP/складені/відновлено.sens"
  printf '%s\n' ':вихід'
} >"$TMP/складені/сеанс.in"
rc=0
"$BIN" --сеанс "$ROOT" <"$TMP/складені/сеанс.in" \
  >"$TMP/складені/сеанс.out" 2>"$TMP/складені/сеанс.err" || rc=$?
test "$rc" -eq 2
cat >"$TMP/складені/очікування.out" <<'EOF'
РЕЗУЛЬТАТ 2 1:1
РЕЗУЛЬТАТ 3 2:10|1:1|24:000000000000000000000000|2:01
РЕЗУЛЬТАТ 4 24:000000000000000000000000
РЕЗУЛЬТАТ 6 1:1
РЕЗУЛЬТАТ 11 1:1
РЕЗУЛЬТАТ 12 2:10|1:1|24:000000000000000000000000|2:01
РЕЗУЛЬТАТ 13 24:000000000000000000000000
EOF
diff -u "$TMP/складені/очікування.out" "$TMP/складені/сеанс.out"
cmp "$TMP/складені/expected.sens" "$TMP/складені/збережено.sens"
cmp "$TMP/складені/expected.sens" "$TMP/складені/відновлено.sens"
test ! -e "$TMP/складені/старе.sens"
test "$(grep -c '^ПОМИЛКА ' "$TMP/складені/сеанс.err")" -eq 5
for n in 1 7 8 9 10; do
  grep -q "^ПОМИЛКА $n " "$TMP/складені/сеанс.err"
  ! grep -q "^РЕЗУЛЬТАТ $n " "$TMP/складені/сеанс.out"
done
grep '^ПОМИЛКА 1 ' "$TMP/складені/сеанс.err" | grep -Fq 'фізичний шлях'
grep '^ПОМИЛКА 7 ' "$TMP/складені/сеанс.err" | grep -Fq 'форма=3'
grep '^ПОМИЛКА 9 ' "$TMP/складені/сеанс.err" | grep -Fq '1..64'
grep -q '0 unfreed memory blocks' "$TMP/складені/сеанс.err"
echo 'CORE4-СЕАНС-КОРЕНІ-ГАРАЗД реальне-виконання=3x2 складене-D2=так W24=opaque T5M-byte-exact=так негативні=5 recovery=так'
