#!/usr/bin/env bash
# G6.82 — перевірка реального x86-64 SUB над exact D6/D12.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "1f1bf676eeac605e065035d9dd2adaae807f1788"
# Sparse authority містить лише потрібні таблиці, НЕ весь CPU-профіль.
# Читаємо обидва pinned свідки з повного незалежного git checkout,
# з exact SHA нижче, ніколи не вимагаємо зайвого файлу у sparse.
git -C sens-oracle show HEAD:lib/domains/d6.lisp | \
  grep -Fq '(001111 (ук відняти-1) (укр відняти-1)'
git -C sens-oracle show HEAD:lib/machine/profile/current-domain-x86-64.lisp | \
  grep -Fq 'домен-шостий відняти-1 fast-path "SUB / точний 64-бітний вхід не менший від одиниці'
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'D6-ВІДНЯТИ-1-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for tool in git fpc timeout objdump readelf cmp grep; do command -v "$tool" >/dev/null;done
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'D6-ВІДНЯТИ-1-БЛОК: немає незалежного pinned SENS' >&2;exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "1f1bf676eeac605e065035d9dd2adaae807f1788"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/ird6sub1/units"
BIN="$ROOT/build/m0.2/ird6sub1/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
 'scripts/test-ird6sub1.pas test-ird6sub1' \
 'src/sensd6sub1elf.lpr sensd6sub1elf' \
 'src/senschyslo.lpr senschyslo'; do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
     -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable" \
     "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2;exit 1;
     }
done
if ! timeout 90s "$BIN/test-ird6sub1" "$TMP" >"$TMP/unit.log" 2>"$TMP/unit.err"; then
  cat "$TMP/unit.log" "$TMP/unit.err" >&2
  echo 'D6-ВІДНЯТИ-1-ПРОВАЛ: FPC unit-test' >&2
  exit 1
fi
if ! grep -Fxq 'D6-8-10' "$TMP/unit.log"; then
  cat "$TMP/unit.log" "$TMP/unit.err" >&2
  echo 'D6-ВІДНЯТИ-1-ПРОВАЛ: контрольний лічильник 8/10' >&2
  exit 1
fi
PASSED=0
for v in 1 2 3 7 15 127 1024 2047; do
  SOURCE="$TMP/$v.sens"
  EXE="$TMP/$v.elf"
  test -s "$SOURCE" && test -s "$EXE"
  # TFileStream створює файл даних без execute-bit: надаємо його тільки
  # після валідації наявності, перед фактичним машинним запуском.
  chmod 500 "$EXE"
  readelf -h "$EXE" | grep -Eq 'Type:[[:space:]]+DYN'
  timeout 5s "$EXE" >"$TMP/$v.machine.sens"
  cmp "$TMP/$v.expected.sens" "$TMP/$v.machine.sens"
  # Другий незалежний frontend CLI породжує ідентичні машинні байти.
  timeout 10s "$BIN/sensd6sub1elf" --скомпілювати-D6 \
    "$SOURCE" "$TMP/$v.cli.elf" >"$TMP/$v.cli.out"
  cmp "$EXE" "$TMP/$v.cli.elf"
  # Машинна інструкція SUB (не готовий literal у write/exit).
  dd if="$EXE" of="$TMP/$v.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 --adjust-vma=0x78 \
     "$TMP/$v.code" >"$TMP/$v.dis"
  grep -Eiq 'sub.*%eax' "$TMP/$v.dis"
  # Текст є лише українською проєкцією машинного результату.
  printf '(відняти-1 %s)\n' "$v" >"$TMP/$v.lisp"
  timeout 60s "$ORACLE" "$TMP/$v.lisp" >"$TMP/$v.oracle" 2>"$TMP/$v.oracle.err" || {
    cat "$TMP/$v.oracle.err" >&2;echo 'D6-ВІДНЯТИ-1-ORACLE-БЛОК' >&2;exit 1;
  }
  test ! -s "$TMP/$v.oracle.err"
  timeout 10s "$BIN/senschyslo" --в-укр D12 \
    "$TMP/$v.machine.sens" >"$TMP/$v.ukr"
  cmp "$TMP/$v.oracle" "$TMP/$v.ukr"
  PASSED=$((PASSED+1))
done
test "$PASSED" -eq 8
# No-clobber: вихідний ELF не можна замінити або непомітно переписати.
if timeout 10s "$BIN/sensd6sub1elf" --скомпілювати-D6 \
  "$TMP/1.sens" "$TMP/1.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err";then
  echo 'D6-ВІДНЯТИ-1-ПРОВАЛ: перезаписаний ELF' >&2;exit 1;
fi
test ! -s "$TMP/occupied.out"
echo 'D6-ВІДНЯТИ-1-ГАРАЗД 8 ELF/SUB 8 pinned SENS oracle 10 negatives no-clobber'
