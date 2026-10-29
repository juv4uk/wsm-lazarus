#!/usr/bin/env bash
# G6.35 — справжній FPC -> допуск ELF64 -> атомарна публікація.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ПУБЛІКАЦІЯ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
command -v readelf >/dev/null
command -v objdump >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p build/m0.2/elfpublish/units build/m0.2/elfpublish/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/elfpublish/units" \
  -FE"$ROOT/build/m0.2/elfpublish/bin" \
  -otest-elfpublish "$ROOT/scripts/test-elfpublish.pas"
timeout 45s "$ROOT/build/m0.2/elfpublish/bin/test-elfpublish" \
  "$ROOT/external/sens" "$TMP"

# Регресія чинного 8-профільного CLI (реальний FPC, x86, 11 негативів).
timeout 120s bash "$ROOT/scripts/test-sensmashyna.sh"
# Регресія незалежного структурного ELF admission (36 фізичних мутацій).
timeout 120s bash "$ROOT/scripts/test-elfgeometry.sh"

CLI="$ROOT/build/m0.2/mashyna/bin/sensmashyna"
for entry in \
  'цитата:d3-001:physical-001' \
  'атом:d3-010:physical-010' \
  'тотожність:d3-101:physical-101'; do
  IFS=: read -r mode label source <<< "$entry"
  ELF="$TMP/cli-$label.elf"
  timeout 10s "$CLI" "--$mode" "$ROOT/external/sens" \
    "$TMP/$source.sens" "$ELF" > "$TMP/cli-output"
  cmp "$ELF" "$TMP/$label.elf"
  readelf -h "$ELF" > "$TMP/elf-header"
  readelf -l "$ELF" > "$TMP/elf-segment"
  grep -F ELF64 "$TMP/elf-header" >/dev/null
  grep -F LOAD "$TMP/elf-segment" >/dev/null
  timeout 5s "$ELF" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/$label.expected.sens"
done

# POSIX O_EXCL: неперезапис реальної цілі та dangling symlink.
cp "$TMP/d3-001.elf" "$TMP/existing.elf"
if timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
  "$TMP/physical-001.sens" "$TMP/existing.elf" \
  >"$TMP/out" 2>"$TMP/err"; then
  echo 'ПУБЛІКАЦІЯ-ПРОВАЛ: дозволено перезапис наявного ELF' >&2; exit 1
fi
cmp "$TMP/existing.elf" "$TMP/d3-001.elf"
test ! -s "$TMP/out"
ln -s "$TMP/missing-object.elf" "$TMP/dangling.elf"
if timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
  "$TMP/physical-001.sens" "$TMP/dangling.elf" \
  >"$TMP/out" 2>"$TMP/err"; then
  echo 'ПУБЛІКАЦІЯ-ПРОВАЛ: дозволено підміну символьного посилання' >&2; exit 1
fi
test -L "$TMP/dangling.elf"
test ! -e "$TMP/missing-object.elf"
test ! -s "$TMP/out"

echo 'ПЕРЕВІРЕНА-ПУБЛІКАЦІЯ-ELF-ФІЗИЧНИЙ-ГАРАЗД CLI=3 регресія-CLI=8 геометрія=36 no-clobber=так машинний-T5M=побайтово'
