#!/usr/bin/env bash
# Бінарні числа D12+: доказ фізичного T5M і людської проєкції.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
# Sparse authority checkout навмисно не матеріалізує всі контракти.
# Читаємо оригінальні Git-об'єкти саме перевіреного pinned HEAD;
# не змінюємо sparse-набір і не підміняємо закон текстовим дублем.
LANGUAGE_CONTRACT=$(git -C external/sens show HEAD:contracts/language-contract-12.lisp)
NUMERIC_CONTRACT=$(git -C external/sens show HEAD:contracts/numeric-domains-ratification.lisp)
grep -Fq '(first-domain . D12)' <<< "$LANGUAGE_CONTRACT"
grep -Fq '(schema . numeric-d12-start-extension-1)' <<< "$NUMERIC_CONTRACT"
grep -Fq '(domain-sequence . (D12 D24 D48 D96 D192))' <<< "$LANGUAGE_CONTRACT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ЧИСЛОВА-ПЛОЩИНА-БЛОК: немає компілятора FPC' >&2
  exit 127
}
mkdir -p build/m0.2/numericplane-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/numericplane-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-numericplane \
  "$ROOT/scripts/test-numericplane.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/numericplane-units" \
  -FE"$ROOT/build/m0.2/bin" -osenschyslo "$ROOT/src/senschyslo.lpr"
./build/m0.2/bin/test-numericplane
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '-2048' > "$TMP/межа.lisp"
./build/m0.2/bin/senschyslo --з-укр D12 "$TMP/межа.lisp" "$TMP/межа.sens"
[[ -s "$TMP/межа.sens" ]] || { echo 'Немає фізичного T5M' >&2; exit 1; }
[[ "$(./build/m0.2/bin/senschyslo --в-укр D12 "$TMP/межа.sens")" == '-2048' ]] || {
  echo 'ЧИСЛОВА-ПЛОЩИНА-ПОМИЛКА: людський проєктор не оборотний' >&2; exit 1;
}
./build/m0.2/bin/senschyslo --в-укр D12 "$TMP/межа.sens" > "$TMP/зворот.lisp"
cmp "$TMP/межа.lisp" "$TMP/зворот.lisp"
if ./build/m0.2/bin/senschyslo --в-укр D24 "$TMP/межа.sens" \
    > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
  echo 'ЧИСЛОВА-ПЛОЩИНА-ПОМИЛКА: неявне D12→D24' >&2; exit 1;
fi
[[ ! -s "$TMP/відмова.out" ]] || { echo 'Частковий stdout' >&2; exit 1; }
printf '%s\n' '2048' > "$TMP/переповнення.lisp"
if ./build/m0.2/bin/senschyslo --з-укр D12 \
  "$TMP/переповнення.lisp" "$TMP/помилка.sens" \
  > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
  echo 'ЧИСЛОВА-ПЛОЩИНА-ПОМИЛКА: переповнення D12' >&2; exit 1;
fi
[[ ! -e "$TMP/помилка.sens" ]] && [[ ! -s "$TMP/відмова.out" ]] || {
  echo 'Частковий фізичний файл або stdout після відмови' >&2; exit 1;
}
if ./build/m0.2/bin/senschyslo --з-укр D12 "$TMP/межа.lisp" "$TMP/межа.sens" \
  > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
  echo 'ЧИСЛОВА-ПЛОЩИНА-ПОМИЛКА: перезаписаний існуючий .sens' >&2;exit 1;
fi
cmp "$TMP/межа.lisp" "$TMP/зворот.lisp"
echo 'ЧИСЛОВА-ПЛОЩИНА-КЛІ-ГАРАЗД укр=.lisp числовий=D12 фізичний=.sens T5M=точний source=не-law'
