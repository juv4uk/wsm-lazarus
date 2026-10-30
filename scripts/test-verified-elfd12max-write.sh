#!/usr/bin/env bash
# G6.217: машинний x86-64 CMP/CMOVL D6:110111 мусить повністю записати D12 T5M.
# ВИКОРИСТОВУЄМО чинний fpc-headless -> test-verified-all; жодних нових workflow/apt.
# Джерело мовних законів — лише pinned external/sens. Тут тільки host Linux I/O.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-МАКС-ЗАПИС-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
for tool in "$FPC_BIN" git timeout readelf objdump dd cmp grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "Д12-МАКС-ЗАПИС-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh >/dev/null
# Pinned D6 — адреса виклику, не dispatch за людським написанням.
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -Fq '(110111 (ук найбільше) (укр найбільше)'
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"
for pair in   'src/sensd12naibilsheelf.lpr sensd12naibilsheelf'   'scripts/test-elfd12max-fixtures.pas test-elfd12max-fixtures'; do
  read -r source program <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh     -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$program"     "$ROOT/$source" >"$TMP/build-$program.log" 2>&1 || {
      cat "$TMP/build-$program.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$program"
done
timeout 20s "$TMP/bin/test-elfd12max-fixtures" "$TMP/fixtures"   >"$TMP/vectors.tsv" 2>"$TMP/fixture.err"
grep -Fq 'D12-MAX-FIXTURES-OK cases=16' "$TMP/fixture.err"
CLI="$TMP/bin/sensd12naibilsheelf"
PASS=0
HOST_NEG=0
RECOVERY=0
for label in 01 04 11 15; do
  ELF="$TMP/$label.elf"
  timeout 20s "$CLI" --найбільше-D12     "$TMP/fixtures/$label-l.sens" "$TMP/fixtures/$label-r.sens" "$ELF"     >"$TMP/$label.build.out" 2>"$TMP/$label.build.err"
  grep -Fq 'machine-cmp-cmovl=1' "$TMP/$label.build.out"
  test ! -s "$TMP/$label.build.err"
  test -x "$ELF"
  readelf -h "$ELF" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  dd if="$ELF" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel     "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'cmov(l|nge)[[:space:]]+eax,ecx' "$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/$label.dis"
  grep -Eiq 'jne[[:space:]]+' "$TMP/$label.dis"
  timeout 10s "$ELF" >"$TMP/$label.actual.sens" 2>"$TMP/$label.run.err"
  test ! -s "$TMP/$label.run.err"
  cmp "$TMP/fixtures/$label-expected.sens" "$TMP/$label.actual.sens"
  PASS=$((PASS+1))
  rc=0
  timeout 10s bash -c 'exec 1>&-; exec "$1"' _ "$ELF"     2>"$TMP/$label.closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.closed.err"
  HOST_NEG=$((HOST_NEG+1))
  rc=0
  timeout 10s "$ELF" >/dev/full 2>"$TMP/$label.full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.full.err"
  HOST_NEG=$((HOST_NEG+1))
  timeout 10s "$ELF" >"$TMP/$label.recovered.sens"     2>"$TMP/$label.recovered.err"
  test ! -s "$TMP/$label.recovered.err"
  cmp "$TMP/fixtures/$label-expected.sens" "$TMP/$label.recovered.sens"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 4 && test "$HOST_NEG" -eq 8 && test "$RECOVERY" -eq 4
# Відмова пошкодженої фізичної форми — без недійсного ELF на диску.
rc=0
timeout 20s "$CLI" --найбільше-D12   "$TMP/fixtures/corrupt.sens" "$TMP/fixtures/04-r.sens"   "$TMP/rejected.elf" >"$TMP/rejected.out" 2>"$TMP/rejected.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/rejected.elf"
test ! -s "$TMP/rejected.out"
grep -Fq 'ELF-D12-ВІДМОВА:' "$TMP/rejected.err"
# Атомарне правило не перезаписувати вже опублікований ELF.
cp "$TMP/04.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$CLI" --найбільше-D12   "$TMP/fixtures/15-l.sens" "$TMP/fixtures/15-r.sens"   "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/04.elf" "$TMP/occupied.elf"
echo "Д12-МАКС-ЗАПИС-PASS elf=$PASS host-negative=$HOST_NEG recovery=$RECOVERY admission-negative=1 no-clobber=1 oracle=NOT_RUN energy=NOT_MEASURED"
