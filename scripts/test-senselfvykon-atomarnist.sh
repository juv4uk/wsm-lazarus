#!/usr/bin/env bash
# G6.51 — перевірка атомарної фізичної публікації справжнього ELF64.
# Ніяких нових SENS законів: тільки чинний pinned T5M → ELF → T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'МАШИННИЙ-ЗАПИС-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
command -v fpc >/dev/null || { echo 'МАШИННИЙ-ЗАПИС-БЛОК: потрібен FPC' >&2; exit 127; }
command -v timeout >/dev/null
command -v stat >/dev/null
command -v cmp >/dev/null

# Повна наявна регресія обов'язкова: 10 ELF, 22 негативи і probe-suite.
timeout 240s bash ./scripts/test-senselfvykon.sh
BIN="$ROOT/build/m0.2/senselfvykon/bin"
CLI="$BIN/senselfvykon"
GEN="$BIN/test-senselfvykon"
[[ -x "$CLI" && -x "$GEN" ]]
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 12s "$GEN" "$TMP"
test -s "$TMP/p01.sens"
test -s "$TMP/p02.sens"
! cmp -s "$TMP/p01.expected.sens" "$TMP/p02.expected.sens" || {
  echo 'МАШИННИЙ-ЗАПИС-ПРОВАЛ: дві відповіді збігаються' >&2;exit 1;
}

# У навмисно відкритій масці каталог/файли НЕ повинні ставати 0644/0666.
# FPC helper закриває приватний inode ДО атомарного fpLink.
(
  umask 000
  timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
    "$TMP/p01.sens" "$TMP/один.sens" >"$TMP/один.out" 2>"$TMP/один.err"
)
cmp "$TMP/один.sens" "$TMP/p01.expected.sens"
[[ $(stat -c '%a' "$TMP/один.sens") == 600 ]]
grep -F 'МАШИННЕ-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД' "$TMP/один.out" >/dev/null

# Два справжніх x86-64 ELF з РІЗНИМИ T5M результатами змагаються за
# одне фізичне ім'я. Рівно один writer здобуває link; інший відхиляється.
WINS_A=0
WINS_B=0
for i in $(seq 1 16); do
  target="$TMP/гонка-$i.sens"
  (
    umask 000
    timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
      "$TMP/p01.sens" "$target" >"$TMP/a-$i.out" 2>"$TMP/a-$i.err"
  ) &
  pa=$!
  (
    umask 000
    timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
      "$TMP/p02.sens" "$target" >"$TMP/b-$i.out" 2>"$TMP/b-$i.err"
  ) &
  pb=$!
  ra=0; rb=0
  wait "$pa" || ra=$?
  wait "$pb" || rb=$?
  [[ -s "$target" ]] || { echo "МАШИННИЙ-ЗАПИС-ПРОВАЛ: відсутня ціль $i" >&2; exit 1; }
  [[ $(stat -c '%a' "$target") == 600 ]] || {
    echo "МАШИННИЙ-ЗАПИС-ПРОВАЛ: права відкрита ціль $i" >&2;exit 1;
  }
  if [[ "$ra" == 0 && "$rb" != 0 ]]; then
    cmp "$target" "$TMP/p01.expected.sens"
    test -s "$TMP/a-$i.out"
    test ! -s "$TMP/b-$i.out"
    grep -F 'МАШИННЕ-ELF-ПОМИЛКА:' "$TMP/b-$i.err" >/dev/null
    WINS_A=$((WINS_A+1))
  elif [[ "$rb" == 0 && "$ra" != 0 ]]; then
    cmp "$target" "$TMP/p02.expected.sens"
    test -s "$TMP/b-$i.out"
    test ! -s "$TMP/a-$i.out"
    grep -F 'МАШИННЕ-ELF-ПОМИЛКА:' "$TMP/a-$i.err" >/dev/null
    WINS_B=$((WINS_B+1))
  else
    echo "МАШИННИЙ-ЗАПИС-ПРОВАЛ: обидва writer-и $i повернули $ra/$rb" >&2
    cat "$TMP/a-$i.err" "$TMP/b-$i.err" >&2
    exit 1
  fi
done
[[ $((WINS_A+WINS_B)) == 16 ]]

# Зайнятий шлях та dangling symlink — відмови без часткового stdout.
printf 'ЧУЖИЙ-ФАЙЛ' > "$TMP/захищено.sens"
cp "$TMP/захищено.sens" "$TMP/контроль"
ln -s "$TMP/немає-цілі.sens" "$TMP/висячий.sens"
for target in "$TMP/захищено.sens" "$TMP/висячий.sens"; do
  if (umask 000; timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
    "$TMP/p01.sens" "$target" >"$TMP/відмова.out" 2>"$TMP/відмова.err"); then
    echo 'МАШИННИЙ-ЗАПИС-ПРОВАЛ: зайняту ціль перезаписано' >&2;exit 1
  fi
  test ! -s "$TMP/відмова.out"
  grep -F 'МАШИННЕ-ELF-ПОМИЛКА:' "$TMP/відмова.err" >/dev/null
done
cmp "$TMP/контроль" "$TMP/захищено.sens"
test -L "$TMP/висячий.sens"
test ! -e "$TMP/немає-цілі.sens"

# Відмова від target не отруїла виконавця: нова фізична відповідь.
(umask 000; timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
  "$TMP/p02.sens" "$TMP/відновлення.sens" >"$TMP/відновлення.out" 2>"$TMP/відновлення.err")
cmp "$TMP/відновлення.sens" "$TMP/p02.expected.sens"
[[ $(stat -c '%a' "$TMP/відновлення.sens") == 600 ]]
if find "$TMP" -maxdepth 1 -type f -name 'sen??????' | grep -q .; then
  echo 'МАШИННИЙ-ЗАПИС-ПРОВАЛ: залишилися тимчасові inode' >&2;exit 1
fi
echo "МАШИННИЙ-ЗАПИС-ГАРАЗД FPC=реальний ELF=виконано гонки=16 перемоги-A=$WINS_A перемоги-B=$WINS_B mode=0600 umask=000 no-clobber=так symlink=відхилено recovery=так T5M=точний"
