#!/usr/bin/env bash
# G6.39 — справжній машинний CLI T5M -> Linux ELF64 -> фізичний T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИННЕ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
command -v cmp >/dev/null
OUT="$ROOT/build/m0.2/senselfvykon"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT/units" "$OUT/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -osenselfvykon "$ROOT/src/senselfvykon.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-senselfvykon "$ROOT/scripts/test-senselfvykon.pas"
timeout 20s "$OUT/bin/test-senselfvykon" "$TMP"
CLI="$OUT/bin/senselfvykon"
PASS=0
for row in \
  'цитата:p01' 'цитата:p02' 'атом:p03' 'атом:p04' \
  'тотожність:p05' 'тотожність:p06' \
  'селектор:p07' 'селектор:p08' \
  'умова:p09' 'умова:p10'; do
  IFS=: read -r mode label <<< "$row"
  answer="$TMP/res-$label.sens"
  if ! timeout 10s "$CLI" "--$mode" "$ROOT/external/sens" \
    "$TMP/$label.sens" "$answer" >"$TMP/stdout" 2>"$TMP/stderr"; then
    echo "МАШИННЕ-ELF-ДІАГНОСТИКА: режим=$mode джерело=$label" >&2
    cat "$TMP/stderr" >&2
    cat "$TMP/stdout" >&2
    exit 1
  fi
  test -s "$answer"
  cmp "$answer" "$TMP/$label.expected.sens"
  grep -F 'T5M=' "$TMP/stdout" >/dev/null
  test ! -s "$TMP/stderr" || grep -F '0 unfreed memory blocks' "$TMP/stderr" >/dev/null
  PASS=$((PASS+1))
done
test "$PASS" -eq 10

NEG=0
reject_to() {
  local target="$1"; shift
  if timeout 10s "$CLI" "$@" "$target" >"$TMP/out" 2>"$TMP/err"; then
    echo 'МАШИННЕ-ELF-ТЕСТ-ПОМИЛКА: заборонений виклик прийнято' >&2
    exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/out"
  grep -F 'ELF-' "$TMP/err" >/dev/null
  NEG=$((NEG+1))
}
reject() {
  local target="$TMP/rejected-$NEG.sens"
  reject_to "$target" "$@"
}
reject --атом "$ROOT/external/sens" "$TMP/p01.sens"
reject --тотожність "$ROOT/external/sens" "$TMP/p01.sens"
reject --селектор "$ROOT/external/sens" "$TMP/p01.sens"
reject --умова "$ROOT/external/sens" "$TMP/p01.sens"
reject --цитата "$ROOT/external/sens" "$TMP/p05.sens"
reject --атом "$ROOT/external/sens" "$TMP/p05.sens"
reject --селектор "$ROOT/external/sens" "$TMP/p05.sens"
reject --умова "$ROOT/external/sens" "$TMP/p05.sens"
reject --цитата "$ROOT/external/sens" "$TMP/bad-t5m.sens"
reject --цитата "$ROOT/external/sens" "$TMP/bare-d1.sens"
reject --атом "$ROOT/external/sens" "$TMP/d12-atom.sens"
reject --умова "$ROOT/external/sens" "$TMP/d12-cond.sens"
reject --умова "$ROOT/external/sens" "$TMP/truncated.sens"
reject --цитата "$ROOT/external/sens" "$TMP/empty.sens"
reject --цитата "$ROOT/external/sens" "$TMP/huge.sens"
reject --цитата "$ROOT/external/sens" "$TMP/absent.sens"
reject --цитата "$TMP/absent-root" "$TMP/p01.sens"
reject --неіснуючий "$ROOT/external/sens" "$TMP/p01.sens"
cp "$TMP/p01.sens" "$TMP/wrong.lisp"
reject --цитата "$ROOT/external/sens" "$TMP/wrong.lisp"
reject_to "$TMP/rejected-format.elf" --цитата "$ROOT/external/sens" "$TMP/p01.sens"
test "$NEG" -eq 20

# Наявні цілі та dangling symlink: атомарна відмова, чужі байти незмінні.
cp "$TMP/p02.expected.sens" "$TMP/existing.sens"
if timeout 10s "$CLI" --цитата "$ROOT/external/sens" \
    "$TMP/p01.sens" "$TMP/existing.sens" >"$TMP/out" 2>"$TMP/err"; then
  echo 'МАШИННЕ-ELF-ТЕСТ-ПОМИЛКА: перезаписано відповідь' >&2; exit 1
fi
cmp "$TMP/existing.sens" "$TMP/p02.expected.sens"
test ! -s "$TMP/out"
grep -F 'ELF-' "$TMP/err" >/dev/null
NEG=$((NEG+1))

ln -s "$TMP/not-present.sens" "$TMP/dangling.sens"
if timeout 10s "$CLI" --атом "$ROOT/external/sens" \
    "$TMP/p04.sens" "$TMP/dangling.sens" >"$TMP/out" 2>"$TMP/err"; then
  echo 'МАШИННЕ-ELF-ТЕСТ-ПОМИЛКА: пошкоджено символьне посилання' >&2; exit 1
fi
test -L "$TMP/dangling.sens"
test ! -e "$TMP/not-present.sens"
test ! -s "$TMP/out"
grep -F 'ELF-' "$TMP/err" >/dev/null
NEG=$((NEG+1))
test "$NEG" -eq 22
test "$(find "$TMP" -maxdepth 1 -type f -name 'sen*' | wc -l)" -eq 0

# Утримуємо чинні 22 ELF, 16 негативів та 36 geometry мутацій.
timeout 180s bash "$ROOT/scripts/test-elfprobe-all.sh"
echo 'МАШИННЕ-ФІЗИЧНЕ-ФАЙЛОВЕ-CI-ГАРАЗД CLI-ELF=10 негативи=22 no-clobber=так symlink=відхилено T5M=побайтово регресія-ELF=22'
