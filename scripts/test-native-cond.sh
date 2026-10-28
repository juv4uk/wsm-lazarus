#!/usr/bin/env bash
# G3.9 — точне фізичне D3:110. SENS — єдине джерело закону.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh

grep -Eq '^[[:space:]]*\(110 \(ук за-умовою\) \(укр за-умовою\)' \
  external/sens/lib/domains/d3.lisp || {
  echo 'УМОВА-БЛОК: не збігається pinned D3:110' >&2; exit 1;
}
for invariant in \
  '(cond-clause . (test expression))' \
  '(cond-test . (D1:0 D1:1))' \
  '(cond-on-D1:1 . select-expression)' \
  '(cond-on-D1:0 . continue)' \
  '(cond-after-exhaustion . D3:000)' \
  '(cond-three-part . forbidden)'; do
  grep -Fq "$invariant" external/sens/contracts/language-contract-12.lisp || {
    echo "УМОВА-БЛОК: не знайдено pinned закон: $invariant" >&2; exit 1;
  }
done
command -v fpc >/dev/null || {
  echo 'УМОВА-БЛОК: Free Pascal недоступний' >&2; exit 127;
}
mkdir -p build/m0.2/native-cond-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/native-cond-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-native-cond \
  "$ROOT/scripts/test-native-cond.pas"
./build/m0.2/bin/test-native-cond

# Реальний SENS-виконавець, а не тільки Pascal unit tests.
# sensvykon збирається в уже чинному тесті G3.4.
bash ./scripts/test-nativeeval.sh
bash ./scripts/test-binaryexec.sh
bash ./scripts/test-sessiond3.sh
./build/m0.2/bin/sensvykon --виконати build/m0.2/native-cond-positive.sens \
  >build/m0.2/native-cond-positive.out
printf '1\n' >build/m0.2/native-cond-expected.out
cmp build/m0.2/native-cond-positive.out build/m0.2/native-cond-expected.out
if ./build/m0.2/bin/sensvykon --виконати build/m0.2/native-cond-negative.sens \
    >build/m0.2/native-cond-negative.out 2>build/m0.2/native-cond-negative.err; then
  echo 'УМОВА-ПРОВАЛ: хибний D3:000 як предикат прийнято' >&2; exit 1;
fi
test ! -s build/m0.2/native-cond-negative.out
grep -Fq 'слово=4' build/m0.2/native-cond-negative.err

# Реальні pinned свідки беруться з gitlink, без текстового fallback.
# У фізичному мосту D3:001 quote ПОКИ свідомо заблокований:
# тому .lisp виконуємо лише через текстовий evaluator, а .sens
# доводимо окремим byte-exact transport roundtrip, НЕ семантичною парою.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C external/sens show HEAD:examples/migrated/smoke-cond.lisp >"$TMP/smoke-cond.lisp"
git -C external/sens show HEAD:examples/migrated/smoke-cond.sens >"$TMP/smoke-cond.sens"
test -s "$TMP/smoke-cond.lisp" && test -s "$TMP/smoke-cond.sens"
./build/m0.2/bin/test-nativeeval external/sens --eval \
  "$(cat "$TMP/smoke-cond.lisp")" >"$TMP/smoke-lisp-result"
cmp "$TMP/smoke-lisp-result" build/m0.2/native-cond-expected.out
fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/native-cond-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
./build/m0.2/bin/senst5m --перегляд "$TMP/smoke-cond.sens" >"$TMP/smoke.words"
./build/m0.2/bin/senst5m --пакувати-слова "$TMP/smoke.words" \
  >"$TMP/smoke-repacked.sens"
cmp "$TMP/smoke-cond.sens" "$TMP/smoke-repacked.sens"
echo 'УМОВА-ЗАКРІПЛЕНИЙ-СВІДОК-ГАРАЗД лисп=укр-виконано сенс=T5M-побайтово цитата-фізична=БЛОК'
echo 'УМОВА-CLI-ГАРАЗД фізичний=T5M/D2/D3 контракти=pinned негативні=так Core4=не-виконується'
