#!/usr/bin/env bash
# G4.7: справжній pinned Core4 .lisp, не семантичний oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'CORE4-ФОРМА-БЛОКЕР: потрібен FPC' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-slice-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-slice-units" -FE"$ROOT/build/m0.2/bin" \
  -osenscore4slice "$ROOT/src/senscore4slice.lpr"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-slice-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4slice "$ROOT/scripts/test-core4slice.pas"
"$ROOT/build/m0.2/bin/test-core4slice" "$ROOT"
CLI="$ROOT/build/m0.2/bin/senscore4slice"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for N in 1 612 1223; do
  "$CLI" --форма "$ROOT" "$N" > "$TMP/перший"
  "$CLI" --форма "$ROOT" "$N" > "$TMP/другий"
  cmp "$TMP/перший" "$TMP/другий"
  test -s "$TMP/перший"
done
"$CLI" --форма "$ROOT" 1 > "$TMP/перша"
grep -Fq '(визначити тотожність' "$TMP/перша"
# .sens — окремий фізичний upstream-свідок; не стверджуємо його round-trip.
git -C external/sens ls-tree HEAD -- lib/core4.sens > "$TMP/двійковий"
grep -Fq 'lib/core4.sens' "$TMP/двійковий"
mkdir -p "$TMP/хибний/external/sens/lib"
reject() {
  if "$@" > "$TMP/неприпустимий-stdout" 2> "$TMP/діагностика"; then
    echo 'CORE4-ФОРМА-ПРОВАЛ: помилково допущений вхід' >&2; exit 1
  fi
  test ! -s "$TMP/неприпустимий-stdout"
  grep -Fq 'CORE4-ФОРМА-ПОМИЛКА' "$TMP/діагностика"
}
for N in 0 -1 1224 абв 1.5; do reject "$CLI" --форма "$ROOT" "$N"; done
reject "$CLI" --невідомо "$ROOT" 1
reject "$CLI" --форма "$TMP/відсутній" 1
printf '(незакритий' > "$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --форма "$TMP/хибний" 1
printf '(\300\257)' > "$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --форма "$TMP/хибний" 1
: > "$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --форма "$TMP/хибний" 1
"$CLI" --форма "$ROOT" 1 > "$TMP/після-помилок"
cmp "$TMP/перша" "$TMP/після-помилок"
echo 'CORE4-ФОРМИ-КЛІ-ГАРАЗД pinned=.lisp фізичний=.sens-окремо негативні=так stdout=атомарний'
