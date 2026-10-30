#!/usr/bin/env bash
# G6.179: 16 справжніх ELF64 і 259 детермінованих мутацій фізичного T5M.
# Жодної семантики Pascal, тільки чинні pinned FPC compiler і fixtures.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout python3 readelf mktemp; do
  command -v "$tool" >/dev/null || {
    echo "МУТАЦІЇ-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МУТАЦІЇ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
FPC_BIN=$(command -v fpc)
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/свідки" \
  >"$TMP/генератор.out" 2>"$TMP/генератор.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/генератор.out"
timeout 240s python3 "$ROOT/scripts/test-widepotikelf-mutatsii.py" \
  --компілятор "$TMP/bin/senswidepotikelf" \
  --свідки "$TMP/свідки"
# Owned: тимчасові .ppu/.o, T5M, ELF і журнали лише в $TMP, cleanup EXIT.
# 1. Чому fixture походить із FPC генератора, а не з текстової .lisp?
# 2. Чому семантичний parity для мутацій тут не стверджується?
# 3. Що означає нульовий stdout при exit=2?
# 4. Як тест відрізняє справжній ELF запуск від успіху компіляції?
