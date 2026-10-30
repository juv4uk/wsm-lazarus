#!/usr/bin/env bash
# Строгий структурний опис pinned Core4 без мовного виконання.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'CORE4-ОПИС-БЛОКЕР: немає FPC' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-manifest-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-manifest-units" \
  -FE"$ROOT/build/m0.2/bin" -osenscore4manifest "$ROOT/src/senscore4manifest.lpr"
CLI="$ROOT/build/m0.2/bin/senscore4manifest"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$CLI" --опис "$ROOT" > "$TMP/перший"
"$CLI" --опис "$ROOT" > "$TMP/другий"
cmp "$TMP/перший" "$TMP/другий"
grep -F 'CORE4-ОПИС-ГАРАЗД' "$TMP/перший"
grep -F 'виконання=ні' "$TMP/перший"
COUNT=$(grep -c '^форма=' "$TMP/перший")
(( COUNT > 10 )) || { echo 'CORE4-ОПИС-ПОМИЛКА: замало форм' >&2; exit 1; }
FIRST=$(sed -n '2p' "$TMP/перший")
[[ "$FIRST" == *'форма=1 вид=список'*'байт=1'* ]] || {
  echo "CORE4-ОПИС-ПОМИЛКА: перша фізична форма: $FIRST" >&2; exit 1;
}
mkdir -p "$TMP/поганий/external/sens/lib"
printf '(незакритий' > "$TMP/поганий/external/sens/lib/core4.lisp"
reject() {
  if "$@" > "$TMP/небажаний" 2> "$TMP/діагностика"; then
    echo 'CORE4-ОПИС-ПОМИЛКА: допущено хибний файл' >&2; exit 1
  fi
  [[ ! -s "$TMP/небажаний" ]] || {
    echo 'CORE4-ОПИС-ПОМИЛКА: неповний stdout' >&2; exit 1;
  }
  grep -Fq 'CORE4-ОПИС-ПОМИЛКА' "$TMP/діагностика"
}
reject "$CLI" --опис "$TMP/поганий"
printf '(\300\257)' > "$TMP/поганий/external/sens/lib/core4.lisp"
reject "$CLI" --опис "$TMP/поганий"
: > "$TMP/поганий/external/sens/lib/core4.lisp"
reject "$CLI" --опис "$TMP/поганий"
reject "$CLI" --опис "$TMP/немає"
reject "$CLI" --невідома "$ROOT"
echo "CORE4-ОПИС-ТЕСТ-ГАРАЗД форм=$COUNT детермінізм=так негативні=так виконання=ні"
