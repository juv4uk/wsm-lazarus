#!/usr/bin/env bash
# Дійсний Lazarus/GTK2 + штатний D1/D3 GC executor: без семантики GUI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for cmd in fpc lazbuild xvfb-run timeout; do
  command -v "$cmd" >/dev/null || {
    echo "ЛКЛ-GC-БЛОК: потрібен $cmd" >&2; exit 127;
  }
done
# Не обходимо чинні перевірки pinned Contract 12, реального
# wsm.binaryexec або механіки GC — їх вимагає цей окремий LCL gate.
bash scripts/test-gcexecution.sh
mkdir -p build/lcl-gc-vykon/bin build/lcl-gc-vykon/units
lazbuild --widgetset=gtk2 --build-all gui/sens-gc-vykon-ogliad.lpi
BIN="$ROOT/build/lcl-gc-vykon/bin/sens-gc-vykon-ogliad"
PACK="$ROOT/build/m0.2/bin/senst5m"
test -x "$BIN" && test -x "$PACK"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '1\n' >"$TMP/атом.words"
printf '10 001 10 0 11 1 01 01\n' >"$TMP/пара.words"
printf '1111111\n' >"$TMP/непідтримано.words"
"$PACK" --пакувати-слова "$TMP/атом.words" >"$TMP/атом.sens"
"$PACK" --пакувати-слова "$TMP/пара.words" >"$TMP/пара.sens"
"$PACK" --пакувати-слова "$TMP/непідтримано.words" >"$TMP/непідтримано.sens"
printf '\363' > "$TMP/зіпсовано.sens"
# Ті самі фізичні свідки виконує наявний CLI (не GUI-копія законів).
"$ROOT/build/m0.2/bin/sensvykon" --виконати-сенс \
  "$TMP/атом.sens" > "$TMP/пряма-відповідь.sens"
cmp "$TMP/атом.sens" "$TMP/пряма-відповідь.sens"
if ! LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=10s 180s \
  xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$TMP/атом.sens" "$TMP/пара.sens" \
  "$TMP/зіпсовано.sens" "$TMP/непідтримано.sens" \
  > "$TMP/лкл-лог" 2> "$TMP/лкл-помилки"; then
  cat "$TMP/лкл-лог" >&2
  cat "$TMP/лкл-помилки" >&2
  echo 'ЛКЛ-GC-ПРОВАЛ: Xvfb/GTK2 відхилив справжні натискання' >&2
  exit 1
fi
test ! -s "$TMP/лкл-помилки"
grep -F 'ЛКЛ-ФІЗИЧНИЙ-GC-ГАРАЗД' "$TMP/лкл-лог"
echo 'ЛКЛ-GC-ЗБІРКА-ГАРАЗД FPC=так Lazarus=GTK2 Xvfb=так T5M=точний Core1=НЕ_ВИКОНАНО'
