#!/usr/bin/env bash
# G3.8: фізичний native D3:101 EQ, SENS закони не виводити з host.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'ТОТОЖНІСТЬ-БЛОК: потрібен FPC' >&2; exit 127; }
grep -Eq '^[[:space:]]*\(101 \(ук тотожне\?\) \(укр тотожне\?\)' \
  external/sens/lib/domains/d3.lisp || {
  echo 'ТОТОЖНІСТЬ-БЛОК: зміщено pinned D3:101' >&2; exit 1;
}
grep -Fq '(eq-operands . admitted-atoms-only)' \
  <(git -C external/sens show HEAD:contracts/language-contract-12.lisp) || {
  echo 'ТОТОЖНІСТЬ-БЛОК: відсутній pinned закон D3 EQ' >&2; exit 1;
}
mkdir -p build/m0.2/native-eq-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/native-eq-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-native-eq "$ROOT/scripts/test-native-eq.pas"
./build/m0.2/bin/test-native-eq
# Регресія тих самих уже злитих нативного та двійкового клієнтів.
bash ./scripts/test-nativeeval.sh
bash ./scripts/test-binaryexec.sh
./build/m0.2/bin/sensvykon --виконати build/m0.2/native-eq-positive.sens \
  > build/m0.2/native-eq-valid.out
printf '1\n' > build/m0.2/native-eq.expected
cmp build/m0.2/native-eq-valid.out build/m0.2/native-eq.expected
if ./build/m0.2/bin/sensvykon --виконати build/m0.2/native-eq-negative.sens \
  >build/m0.2/native-eq-invalid.out 2>build/m0.2/native-eq-invalid.err; then
  echo 'ТОТОЖНІСТЬ-ПРОВАЛ: прийнято порожній D3 замість атома' >&2; exit 1
fi
test ! -s build/m0.2/native-eq-invalid.out
grep -Fq 'слово=3' build/m0.2/native-eq-invalid.err
echo 'ТОТОЖНІСТЬ-ВИКОНАННЯ-ГАРАЗД T5M=так FPC=так D3:101=так негативні=так oracle=не-заявлено'
