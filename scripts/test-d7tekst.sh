#!/usr/bin/env bash
# G1.22 — реальний FPC, український UTF-8 та binary pinned D7 v2.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
mkdir -p build/m0.2/d7tekst/units build/m0.2/d7tekst/bin
for target in test-d7tekst sensd7tekst; do
  if [[ "$target" == test-d7tekst ]]; then src=scripts/test-d7tekst.pas
  else src=src/sensd7tekst.lpr; fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/d7tekst/units" \
    -FE"$ROOT/build/m0.2/d7tekst/bin" \
    -o"$target" "$ROOT/$src"
done
timeout 35s "$ROOT/build/m0.2/d7tekst/bin/test-d7tekst"
CLI="$ROOT/build/m0.2/d7tekst/bin/sensd7tekst"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s' 'Привіт, світ! (Д7) ₴' > "$TMP/слова.txt"
timeout 5s "$CLI" --ук-у-сенс "$TMP/слова.txt" > "$TMP/фізичний.sens"
test -s "$TMP/фізичний.sens"
timeout 5s "$CLI" --сенс-у-ук "$TMP/фізичний.sens" > "$TMP/повернено.txt"
cmp "$TMP/слова.txt" "$TMP/повернено.txt"

printf '\363' > "$TMP/пошкоджено.sens"
for item in "$TMP/пошкоджено.sens" "$TMP/неіснує.sens"; do
  if timeout 5s "$CLI" --сенс-у-ук "$item" >"$TMP/поганий.stdout" 2>"$TMP/поганий.stderr"; then
    echo 'Д7-ТЕКСТ-БЛОК: malformed physical accepted' >&2;exit 1
  fi
  test ! -s "$TMP/поганий.stdout"
  grep -Fq 'Д7-ТЕКСТ-ПОМИЛКА:' "$TMP/поганий.stderr"
done
printf 'A' > "$TMP/неук.txt"
if timeout 5s "$CLI" --ук-у-сенс "$TMP/неук.txt" \
   >"$TMP/поганий.stdout" 2>"$TMP/поганий.stderr"; then
  echo 'Д7-ТЕКСТ-БЛОК: unknown glyph accepted' >&2;exit 1
fi
test ! -s "$TMP/поганий.stdout"
grep -Fq 'Д7-ТЕКСТ-ПОМИЛКА:' "$TMP/поганий.stderr"
echo 'Д7-ТЕКСТ-CLI-ГАРАЗД українська=точно binary=.sens D7=пинований'
