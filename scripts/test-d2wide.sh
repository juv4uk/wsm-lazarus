#!/usr/bin/env bash
# G1.10: native FPC wide D2 and real pinned SENS corpus.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
command -v git >/dev/null
mkdir -p build/m0.2/d2wide-units build/m0.2/d2wide-bin
UNITS="$ROOT/build/m0.2/d2wide-units"
BIN="$ROOT/build/m0.2/d2wide-bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
 -FU"$UNITS" -FE"$BIN" -otest-d2wide "$ROOT/scripts/test-d2wide.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
 -FU"$UNITS" -FE"$BIN" -osensstruktura "$ROOT/src/sensstruktura.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
 -FU"$UNITS" -FE"$BIN" -osenst5m "$ROOT/src/senst5m.lpr"
bash ./scripts/test-d2source.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UPSTREAM="$ROOT/external/sens"
PIN=$(git -C "$UPSTREAM" rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
[[ "$PIN" == "$GITLINK" ]] || { echo 'ШИРОКИЙ-D2-БЛОК: pin drift' >&2; exit 1; }
STEM="tests/semantic/d5-d12-numberp-law"
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM.sens" > "$TMP/pinned.sens"
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM" > "$TMP/pinned.bits"
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM.lisp" > "$TMP/pinned.lisp"
test -s "$TMP/pinned.sens"
test -s "$TMP/pinned.bits"
test -s "$TMP/pinned.lisp"
grep -F '(число? (частка 1 3))' "$TMP/pinned.lisp" > /dev/null
"$BIN/senst5m" --перегляд "$TMP/pinned.sens" > "$TMP/physical.bits"
cmp "$TMP/pinned.bits" "$TMP/physical.bits"
"$BIN/test-d2wide" "$TMP/pinned.sens"
"$BIN/sensstruktura" --структура "$TMP/pinned.sens" > "$TMP/tree.tsv"
grep -F $'7\t2\tW24:000000000000000000000001' "$TMP/tree.tsv" > /dev/null
grep -F $'9\t2\tW24:000000000000000000000011' "$TMP/tree.tsv" > /dev/null
grep -F $'1\t0\tD2:відкрити' "$TMP/tree.tsv" > /dev/null
if grep -F 'D24:' "$TMP/tree.tsv" >/dev/null; then
  echo 'ШИРОКИЙ-D2-ПОМИЛКА: ширина не наділяє закон числовим доменом' >&2
  exit 1
fi
cat "$TMP/pinned.sens" > "$TMP/corrupt.sens"
printf '\363' >> "$TMP/corrupt.sens"
for bad in corrupt.sens відсутній.sens; do
  if "$BIN/sensstruktura" --структура "$TMP/$bad" \
    > "$TMP/failed.out" 2>"$TMP/failed.err"; then
    echo "ШИРОКИЙ-D2-ПОМИЛКА: помилковий файл $bad прийнято" >&2
    exit 1
  fi
  test ! -s "$TMP/failed.out"
  grep -F 'СТРУКТУРА-ПОМИЛКА' "$TMP/failed.err" > /dev/null
done
if "$BIN/sensstruktura" --структура "$TMP/pinned.lisp" >"$TMP/failed.out" 2>"$TMP/failed.err"; then
  echo 'ШИРОКИЙ-D2-ПОМИЛКА: .lisp прийнято як фізичний .sens' >&2; exit 1
fi
test ! -s "$TMP/failed.out"
if "$BIN/sensstruktura" --тлумачити "$TMP/pinned.sens" >"$TMP/failed.out" 2>"$TMP/failed.err"; then
  echo 'ШИРОКИЙ-D2-ПОМИЛКА: неіснуючу команду допущено' >&2; exit 1
fi
test ! -s "$TMP/failed.out"
echo "ШИРОКИЙ-D2-CLI-ГАРАЗД pinned=$PIN фізичний-T5M=ідентичний W24=2 семантика=не-доведено"
