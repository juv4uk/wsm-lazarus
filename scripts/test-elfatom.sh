#!/usr/bin/env bash
# G6.9: фізичне виконання замкненого D3:010 в машинному ELF64 Linux.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'НАТИВНИЙ-АТОМ-БЛОК: потрібен Linux x86-64' >&2; exit 1;
}
FPC_BIN=${FPC:-fpc}
mkdir -p build/m0.2/elfatom/units build/m0.2/elfatom/bin
for target in test-elfatom sensatomelf sensvykon; do
  if [[ $target == test-elfatom ]]; then src=scripts/test-elfatom.pas
  else src=src/$target.lpr
  fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/elfatom/units" -FE"$ROOT/build/m0.2/elfatom/bin" \
    -o"$target" "$src"
done
./build/m0.2/elfatom/bin/test-elfatom
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$ROOT/build/m0.2/elfatom/bin"
for label in atom-zero atom-one atom-empty atom-d3-empty atom-cons atom-cons-empty atom-cons-cons atom-atom-cons atom-atom atom-nested-cons; do
  input="build/m0.2/elfatom/$label.sens"
  "$BIN/sensatomelf" --породити "$input" "$TMP/$label.elf" >"$TMP/$label.compiler"
  test -x "$TMP/$label.elf"
  cmp "build/m0.2/elfatom/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  readelf -l "$TMP/$label.elf" > "$TMP/$label.phdr"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.phdr" >/dev/null
  timeout 5s "$TMP/$label.elf" > "$TMP/$label.machine"
  timeout 10s "$BIN/sensvykon" --виконати "$input" > "$TMP/$label.oracle"
  cmp "$TMP/$label.machine" "$TMP/$label.oracle"
  cmp "$TMP/$label.machine" "build/m0.2/elfatom/$label.expected.out"
done
# Фізичний свідок самого pinned juv4uk/sens: його складний EQ/ATOM
# закон НЕ входить до вузької підмножини цього backend.
UPSTREAM="$ROOT/external/sens"
PIN=$(git -C "$UPSTREAM" rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
[[ "$PIN" == "$GITLINK" ]] || {
  echo 'НАТИВНИЙ-АТОМ-БЛОК: зовнішній SENS не на pinned gitlink' >&2; exit 1;
}
STEM='tests/semantic/d3-eq-atom-boundary-law'
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM.sens" > "$TMP/pinned.sens"
timeout 70s git -C "$UPSTREAM" show "$PIN:$STEM.lisp" > "$TMP/pinned.lisp"
test -s "$TMP/pinned.sens"
grep -F 'атом?' "$TMP/pinned.lisp" >/dev/null
if "$BIN/sensatomelf" --породити "$TMP/pinned.sens" "$TMP/pinned.elf" \
    > "$TMP/pinned.out" 2> "$TMP/pinned.err"; then
  echo 'НАТИВНИЙ-АТОМ-ПОМИЛКА: неуповноважений pinned закон допущено' >&2
  exit 1
fi
test ! -e "$TMP/pinned.elf"
test ! -s "$TMP/pinned.out"
grep -F 'НАТИВНИЙ-АТОМ-ПОМИЛКА' "$TMP/pinned.err" >/dev/null
# Помилка допуску не створює ELF; старі файли не перезаписуються.
printf '\363' > "$TMP/invalid.sens"
for bad in "$TMP/invalid.sens" missing.sens; do
  if "$BIN/sensatomelf" --породити "$bad" "$TMP/reject.elf" \
      >"$TMP/bad.out" 2>"$TMP/bad.err"; then
    echo 'НАТИВНИЙ-АТОМ-ПОМИЛКА: неприйнятний фізичний ввід пройшов' >&2;exit 1
  fi
  test ! -e "$TMP/reject.elf"
  test ! -s "$TMP/bad.out"
  grep -F 'НАТИВНИЙ-АТОМ-ПОМИЛКА' "$TMP/bad.err" >/dev/null
done
printf 'збережений\n' > "$TMP/occupied.elf"
if "$BIN/sensatomelf" --породити build/m0.2/elfatom/atom-zero.sens \
    "$TMP/occupied.elf" > "$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'НАТИВНИЙ-АТОМ-ПОМИЛКА: перезаписано існуючий файл' >&2;exit 1
fi
printf 'збережений\n' > "$TMP/original"
cmp "$TMP/occupied.elf" "$TMP/original"
test ! -s "$TMP/bad.out"
echo 'НАТИВНИЙ-АТОМ-ВИКОНАННЯ-ГАРАЗД ELF64=x86-64 D3:010=машинна-операція 10-випадків=побайтово-однаково LCL=непотрібно'
