#!/usr/bin/env bash
# Фізичний FPC-тест підмножини: .sens T5M/D2 -> чинний D3-виконавець.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'ДВІЙКОВЕ-ВИКОНАННЯ-БЛОК: не знайдено Free Pascal' >&2
  exit 127
}
mkdir -p build/m0.2/binaryexec-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binaryexec-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-binaryexec "$ROOT/scripts/test-binaryexec.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binaryexec-units" -FE"$ROOT/build/m0.2/bin" \
  -osensvykon "$ROOT/src/sensvykon.lpr"
./build/m0.2/bin/test-binaryexec

# Перевірка відсутності прихованого semantic dispatch через «ук».
# Фізичні біти/доменні рядки з pinned SENS залишаються 1:1;
# тільки для МЕХАНІЧНОГО тесту всі «ук» у D1/D3 видалені.
# Це НЕ новий authority і НЕ оракул SENS.
MOCK="$ROOT/build/m0.2/direct-exact-no-uk"
mkdir -p "$MOCK/lib/domains"
for d in {1..10}; do
  cp "$ROOT/external/sens/lib/domains/d$d.lisp" "$MOCK/lib/domains/d$d.lisp"
done
for d in 1 3; do
  # Порожнє pinned (ук ()) уже канонічне: НЕ захоплювати
  # початкову дужку через [^)]*, щоб не утворити зайвий ')'.
  # D1/D3 містять лише непорожні бездужкові ук-атоми або ().
  sed -E 's/\(ук [^()]+\)/(ук ())/g' \
    "$ROOT/external/sens/lib/domains/d$d.lisp" \
    > "$MOCK/lib/domains/d$d.lisp"
done
projection_result=$(./build/m0.2/bin/test-binaryexec "$MOCK")
printf '%s\n' "$projection_result"
[[ "$projection_result" == *'ДВІЙКОВИЙ-ПРЯМИЙ-ГАРАЗД ук_D1_D3=відсутні'* ]] || {
  echo 'ДВІЙКОВИЙ-ПРЯМИЙ-ПОМИЛКА: немає доказу незалежності від ук' >&2
  exit 1
}
rm -rf "$MOCK"

result=$(./build/m0.2/bin/sensvykon --виконати build/m0.2/binaryexec-valid.sens)
[[ "$result" == '(1)' ]] || { echo "ДВІЙКОВИЙ-КЛІ-ПОМИЛКА: $result" >&2; exit 1; }
if ./build/m0.2/bin/sensvykon --виконати build/m0.2/binaryexec-invalid.sens \
   >build/m0.2/binaryexec-invalid.out 2>build/m0.2/binaryexec-invalid.err; then
  echo 'ДВІЙКОВИЙ-КЛІ-ПОМИЛКА: хибна арність цитати прийнята' >&2
  exit 1
fi
[[ ! -s build/m0.2/binaryexec-invalid.out ]] || {
  echo 'ДВІЙКОВИЙ-КЛІ-ПОМИЛКА: частковий stdout при помилці' >&2; exit 1;
}
grep -q 'слово=2' build/m0.2/binaryexec-invalid.err || {
  cat build/m0.2/binaryexec-invalid.err >&2; exit 1;
}
grep -q 'unsupported computed native head' build/m0.2/binaryexec-invalid.err || {
  echo 'ДВІЙКОВИЙ-ПРЯМИЙ-ПОМИЛКА: UTF-8 діагностика втрачена' >&2
  cat build/m0.2/binaryexec-invalid.err >&2
  exit 1
}
# G3.35: координати походять ЛИШЕ з canonical T5M/physloc, не
# з рядків «укр» і не з host-індексів. Фізичні [trit) точні,
# а [byte) — envelope (слова можуть фізично ділити один байт).
# Існуючий бінарний свідок має невикличний D3:000 у другому слові:
# W2 на [0,2), separator=2, W3 на [3,6), bytes=[0,2).
grep -Fq 'слово=2 трити=[3,6) байти=[0,2)' \
  build/m0.2/binaryexec-invalid.err || {
  echo 'ДВІЙКОВИЙ-АДРЕСИ-ПРОВАЛ: неправильні фізичні координати W3' >&2
  cat build/m0.2/binaryexec-invalid.err >&2; exit 1;
}

# Власна фізична EOF-подія: відкритий D2 root зі словами W2:10,W1:1.
# Кінець за чотирма змістовними тритами (останній 0-based boundary),
# після T5M padding byte-count дорівнює одному.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/binaryexec-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
printf '10 1\n' > build/m0.2/binaryexec-eof.words
./build/m0.2/bin/senst5m --пакувати-слова \
  build/m0.2/binaryexec-eof.words \
  >build/m0.2/binaryexec-eof.sens
if ./build/m0.2/bin/sensvykon --виконати build/m0.2/binaryexec-eof.sens \
  >build/m0.2/binaryexec-eof.out 2>build/m0.2/binaryexec-eof.err; then
  echo 'ДВІЙКОВИЙ-АДРЕСИ-ПРОВАЛ: незакритий D2 допущено' >&2; exit 1;
fi
test ! -s build/m0.2/binaryexec-eof.out
grep -Fq 'слово=3 кінець-файлу трити=[4,4) байти=[1,1)' \
  build/m0.2/binaryexec-eof.err || {
  echo 'ДВІЙКОВИЙ-АДРЕСИ-ПРОВАЛ: EOF не є точним порожнім інтервалом' >&2
  cat build/m0.2/binaryexec-eof.err >&2; exit 1;
}

# Зіпсований T5M не має допущеного фізичного слова: WordIndex=0,
# не можна повертати [0,5) лише на підставі довжини файлу.
printf '\363' > build/m0.2/binaryexec-corrupt.sens
if ./build/m0.2/bin/sensvykon --виконати build/m0.2/binaryexec-corrupt.sens \
  >build/m0.2/binaryexec-corrupt.out \
  2>build/m0.2/binaryexec-corrupt.err; then
  echo 'ДВІЙКОВИЙ-АДРЕСИ-ПРОВАЛ: некоректні T5M байти допущено' >&2
  exit 1
fi
test ! -s build/m0.2/binaryexec-corrupt.out
grep -Fq 'слово=0' build/m0.2/binaryexec-corrupt.err
if grep -Fq 'трити=[' build/m0.2/binaryexec-corrupt.err; then
  echo 'ДВІЙКОВИЙ-АДРЕСИ-ПРОВАЛ: вигадано координати для corrupt T5M' >&2
  exit 1
fi

# Повторний реальний виклик не залежить від зіпсованих попередників.
result=$(./build/m0.2/bin/sensvykon --виконати \
  build/m0.2/binaryexec-valid.sens)
[[ "$result" == '(1)' ]] || {
  echo 'ДВІЙКОВИЙ-АДРЕСИ-ПРОВАЛ: змінено успішний результат' >&2; exit 1;
}
# G3.37: реальні чисті T5M-байти від виконаної форми (D1:1),
# не WriteLn(рядок), не .lisp, не host length/status кадр.
# senst5m є вже зібраним ВИЩЕ та використовує pinned codec.
printf '1\n' > build/m0.2/binaryexec-atom.words
./build/m0.2/bin/senst5m --пакувати-слова \
  build/m0.2/binaryexec-atom.words \
  >build/m0.2/binaryexec-atom.sens
./build/m0.2/bin/sensvykon --виконати-сенс \
  build/m0.2/binaryexec-atom.sens \
  >build/m0.2/binaryexec-atom.answer.sens \
  2>build/m0.2/binaryexec-atom.answer.err
test ! -s build/m0.2/binaryexec-atom.answer.err
cmp build/m0.2/binaryexec-atom.sens \
  build/m0.2/binaryexec-atom.answer.sens || {
  echo 'ДВІЙКОВИЙ-ВИВІД-ПРОВАЛ: додано newline/текст або змінено D1' >&2
  exit 1
}
result=$(./build/m0.2/bin/sensvykon --виконати \
  build/m0.2/binaryexec-atom.sens)
[[ "$result" == '1' ]] || {
  echo 'ДВІЙКОВИЙ-ВИВІД-ПРОВАЛ: зламано попередній текстовий CLI' >&2
  exit 1
}
for bad in binaryexec-invalid binaryexec-eof binaryexec-corrupt; do
  if ./build/m0.2/bin/sensvykon --виконати-сенс \
    "build/m0.2/$bad.sens" >"build/m0.2/$bad.raw" \
    2>"build/m0.2/$bad.raw.err"; then
    echo "ДВІЙКОВИЙ-ВИВІД-ПРОВАЛ: відхилену форму $bad прийнято" >&2
    exit 1
  fi
  test ! -s "build/m0.2/$bad.raw" || {
    echo "ДВІЙКОВИЙ-ВИВІД-ПРОВАЛ: частковий T5M stdout $bad" >&2
    exit 1
  }
  test -s "build/m0.2/$bad.raw.err"
done
if ./build/m0.2/bin/sensvykon --виконати-сенс \
  build/m0.2/binaryexec-atom.lisp \
  >build/m0.2/binaryexec-atom.wrong.out \
  2>build/m0.2/binaryexec-atom.wrong.err; then
  echo 'ДВІЙКОВИЙ-ВИВІД-ПРОВАЛ: .lisp допущено як двійковий файл' >&2
  exit 1
fi
test ! -s build/m0.2/binaryexec-atom.wrong.out
if ./build/m0.2/bin/sensvykon --невідомий \
  build/m0.2/binaryexec-atom.sens \
  >build/m0.2/binaryexec-atom.mode.out \
  2>build/m0.2/binaryexec-atom.mode.err; then
  echo 'ДВІЙКОВИЙ-ВИВІД-ПРОВАЛ: неіснуючий режим прийнято' >&2
  exit 1
fi
test ! -s build/m0.2/binaryexec-atom.mode.out
echo 'ДВІЙКОВИЙ-ВИВІД-ГАРАЗД фізичний=D1:1 байти=точні newline=немає відмови=без-stdout проекція=незмінна'

echo 'ДВІЙКОВІ-ФІЗИЧНІ-АДРЕСИ-ГАРАЗД W3=[3,6)/[0,2) EOF=[4,4)/[1,1) зіпсований-T5M=без-координат stdout=атомарний'
echo 'ДВІЙКОВИЙ-КЛІ-ОК фізичний=.sens вихід=тільки_після_перевірки'
