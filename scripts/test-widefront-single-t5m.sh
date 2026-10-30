#!/usr/bin/env bash
# G6: регресійний свідок одного фізичного читання у СПІЛЬНОМУ компіляторі.
# Незалежні pinned SENS REPL виклики тут НЕ запускаються; чинний
# test-irwidefront перевіряє 16 фізичних машин + 24 негативи.
# Питання: хто зберігає exact T5M? Чому Width важливий?
# Хто звільняє локальний WideIR? Чому ця перевірка не дає джоулів?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in fpc timeout git grep tee mktemp; do
  command -v "$tool" >/dev/null || { echo "WIDEFRONT-ONCE-BLOCK tool=$tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'WIDEFRONT-ONCE-BLOCK target=Linux-x86_64' >&2; exit 127;
}
test "$(fpc -iV)" = '3.2.2' || {
  echo 'WIDEFRONT-ONCE-BLOCK FPC!=3.2.2' >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
PIN=$(git -C external/sens rev-parse HEAD)
test -n "$PIN"
SOURCE=src/wsm.irwidefront.pas
# Статичний guard не є доказом runtime сам по собі, але відхиляє
# випадкове повернення зайвого першого проходу в цей entrypoint.
test "$(grep -Fc '  BuildWideIR(ProgramPhysical,Tables,IR);' "$SOURCE")" -eq 1
if grep -Eq '^[[:space:]]+(DecodeT5M|EncodeT5M)\(' "$SOURCE"; then
  echo 'WIDEFRONT-ONCE-FAIL restored-duplicate-codec' >&2; exit 1;
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Справжній FPC checked + фізичний upstream fixture + два різні
# механічні backend для 16 програм: x86 machine stdout T5M,
# byte-identical donor ELF, 24 відмови/no-clobber/recovery.
SENS_ORACLE_BIN="" timeout 240s bash scripts/test-irwidefront.sh \
  >"$TMP/main.log" 2>"$TMP/main.err" || {
    tail -n 70 "$TMP/main.log" "$TMP/main.err" >&2; exit 1;
  }
grep -Fq 'СПІЛЬНИЙ-WIDEIR-ГАРАЗД physical=16 machine=16' "$TMP/main.log"
grep -Fq 'negatives=24' "$TMP/main.log"
grep -Fq 'byte-identical=так' "$TMP/main.log"
echo "WIDEFRONT-ONE-DECODE-OK FPC=3.2.2 physical=16 machine=16 negatives=24 canonical=exact donor-ELF=identical oracle=NOT-RUN energy=NOT-MEASURED pin=$PIN"
