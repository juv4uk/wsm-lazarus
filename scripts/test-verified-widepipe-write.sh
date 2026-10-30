#!/usr/bin/env bash
# G6.245 — реальні Linux stdout-відмови потокового T5M→WideIR→ELF64.
# Жодних нових законів SENS: це перевірка host ABI та точних машинних байтів.
# Наявний verified-all підхоплює файл без нового FPC workflow чи apt.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ШИРОКИЙ-ЗАПИС-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout git readelf cmp grep chmod mktemp; do
  command -v "$tool" >/dev/null || {
    echo "ШИРОКИЙ-ЗАПИС-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "ШИРОКИЙ-ЗАПИС-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ -s "$f" ]] || continue
      echo "--- $f" >&2
      tail -n 20 "$f" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
    cat "$TMP/$name.build" >&2; exit 1;
  }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.log"
SOURCE="$TMP/physical/09.sens"
EXPECTED="$TMP/physical/09.expected.sens"
test -s "$SOURCE"
test -s "$EXPECTED"
MODE=--скомпілювати-фізичний-потік
BIN="$TMP/bin/senswidepotikelf"

# Позитив: фізичний T5M справді компілюється та виконується як ELF64 PIE.
timeout 25s "$BIN" "$MODE" <"$SOURCE" >"$TMP/before.elf" 2>"$TMP/before.err"
test -s "$TMP/before.elf"
readelf -h "$TMP/before.elf" >"$TMP/before.header"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/before.header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/before.header"
chmod 700 "$TMP/before.elf"
timeout 5s "$TMP/before.elf" >"$TMP/before.sens" 2>"$TMP/before.machine.err"
test ! -s "$TMP/before.machine.err"
cmp "$EXPECTED" "$TMP/before.sens"

# Відмови мають бути помилками, а не тихим «успіхом» чи фальшивим ELF.
FULL_RC=0
timeout 25s "$BIN" "$MODE" <"$SOURCE" >/dev/full 2>"$TMP/full.err" || FULL_RC=$?
test "$FULL_RC" -eq 2
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/full.err"
CLOSED_RC=0
(
  exec 1>&-
  timeout 25s "$BIN" "$MODE" <"$SOURCE" 2>"$TMP/closed.err"
) || CLOSED_RC=$?
test "$CLOSED_RC" -eq 2
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/closed.err"

# Структурно зламане фізичне джерело відхиляється ДО запису ELF stdout.
BAD_RC=0
timeout 25s "$BIN" "$MODE" \
  <"$TMP/physical/bad-t5m.sens" >"$TMP/bad.elf" 2>"$TMP/bad.err" || BAD_RC=$?
test "$BAD_RC" -eq 2
test ! -s "$TMP/bad.elf"
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/bad.err"

# Після негативів знову маємо ТОЙ САМИЙ ELF і канонічний результат.
timeout 25s "$BIN" "$MODE" <"$SOURCE" >"$TMP/after.elf" 2>"$TMP/after.err"
cmp "$TMP/before.elf" "$TMP/after.elf"
chmod 700 "$TMP/after.elf"
timeout 5s "$TMP/after.elf" >"$TMP/after.sens" 2>"$TMP/after.machine.err"
test ! -s "$TMP/after.machine.err"
cmp "$EXPECTED" "$TMP/after.sens"
echo 'VERIFIED-WIDEPIPE-WRITE-PASS FPC=checked ELF64=2 negative=3 recovery=byte-identical oracle=EXISTING-SUITE energy=NOT-MEASURED'
