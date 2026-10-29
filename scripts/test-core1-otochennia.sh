#!/usr/bin/env bash
# #509: незалежність фізичного індексу Core1 від host-локалі та UTF-8 шляху.
# Перевіряє лише наявний T5M/D2/D7 механізм, не визначає законів SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

for cmd in timeout cmp cp mktemp grep; do
  command -v "$cmd" >/dev/null || {
    echo "CORE1-ОТОЧЕННЯ-БЛОК: немає $cmd" >&2; exit 127;
  }
done
FPC_BIN={FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'CORE1-ОТОЧЕННЯ-БЛОК: немає FPC' >&2; exit 127;
}
./scripts/check-pin.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenscore1indeks "$ROOT/src/senscore1indeks.lpr" \
  >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2; exit 1;
  }
BIN="$TMP/bin/senscore1indeks"
test -x "$BIN"

# Core1 фізичний; проєкція .lisp та host-переклад не беруть участі.
SOURCE="$ROOT/external/sens/lib/core1.sens"
test -s "$SOURCE" || {
  echo 'CORE1-ОТОЧЕННЯ-БЛОК: немає pinned core1.sens' >&2; exit 1;
}
COPY="$TMP/український корінь із пробілами"
mkdir -p "$COPY/external/sens/lib"
cp "$SOURCE" "$COPY/external/sens/lib/core1.sens"
cmp "$SOURCE" "$COPY/external/sens/lib/core1.sens"

# Всі stdout перевіряємо як БАЙТИ: жодних імен або числових замін ключів.
run() {
  local locale="$1" tz="$2" out="$3" root="$4" action="$5"
  shift 5
  env LC_ALL="$locale" TZ="$tz" timeout 60s "$BIN" "$action" "$root" "$@" \
    >"$out" 2>"$out.err"
  test ! -s "$out.err" || {
    echo "CORE1-ОТОЧЕННЯ-ПРОВАЛ: stderr за $locale $tz" >&2
    cat "$out.err" >&2; exit 1;
  }
}
run C UTC "$TMP/опис-A" "$ROOT" --опис
run C.UTF-8 Europe/Kyiv "$TMP/опис-Б" "$COPY" --опис
cmp "$TMP/опис-A" "$TMP/опис-Б"
grep -Fxq 'CORE1-ІНДЕКС-ГАРАЗД визначень=96 унікальних=96 перше-слово=1 пошук=D7 виконання=ні' "$TMP/опис-A"

for n in 1 48 96; do
  run C UTC "$TMP/ключ-$n" "$ROOT" --ключ "$n"
  run C.UTF-8 Europe/Kyiv "$TMP/ключ-укр-$n" "$COPY" --ключ "$n"
  cmp "$TMP/ключ-$n" "$TMP/ключ-укр-$n"
  test -s "$TMP/ключ-$n"

  run C UTC "$TMP/форма-$n" "$ROOT" --форма "$n"
  run C.UTF-8 Europe/Kyiv "$TMP/форма-укр-$n" "$COPY" --форма "$n"
  cmp "$TMP/форма-$n" "$TMP/форма-укр-$n"
  test -s "$TMP/форма-$n"

  run C.UTF-8 Europe/Kyiv "$TMP/пошук-$n" "$COPY" --знайти "$TMP/ключ-$n"
  cmp "$TMP/форма-$n" "$TMP/пошук-$n"
done

# Пошкодження підставного фізичного файлу: rc=2 та нуль байтів stdout.
printf '\377' >"$COPY/external/sens/lib/core1.sens"
for locale in C C.UTF-8; do
  rc=0
  env LC_ALL="$locale" TZ=Europe/Kyiv timeout 60s "$BIN" --ключ "$COPY" 1 \
    >"$TMP/відмова.out" 2>"$TMP/відмова.err" || rc=$?
  if [[ "$rc" != 2 || -s "$TMP/відмова.out" ]] ||
      ! grep -Fq 'CORE1-ІНДЕКС-ВІДМОВА:' "$TMP/відмова.err"; then
    echo "CORE1-ОТОЧЕННЯ-ПРОВАЛ: пошкоджений T5M; locale=$locale rc=$rc" >&2
    cat "$TMP/відмова.err" >&2; exit 1
  fi
done

# Один і той самий процес запуску після відмов не залишив stale фізичних даних.
cp "$SOURCE" "$COPY/external/sens/lib/core1.sens"
run C.UTF-8 Europe/Kyiv "$TMP/відновлено" "$COPY" --форма 96
cmp "$TMP/форма-96" "$TMP/відновлено"
echo 'CORE1-ОТОЧЕННЯ-ГАРАЗД FPC=так exact-D7=1,48,96 фізичний-T5M=побайтово локалі=2 часові-пояси=2 український-шлях=так відмови=2 відновлення=так виконання=ні'
