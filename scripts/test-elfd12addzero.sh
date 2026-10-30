#!/usr/bin/env bash
# G6.85: один машинний ADD + TEST/SETE/MOVZX → канонічний D1 T5M.
set -euo pipefail
trap 'c=$?; echo "D12-НУЛЬ-КОМПОЗИЦІЯ-ЗБІЙ код=$c рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01000 (ук нуль?) (укр нуль?)'
git -C external/sens show HEAD:lib/machine/profile/current-domain-x86-64.lisp |
  grep -Fq 'CMP+SETE+MOVZX / точний внутрішній біт цілого числа'
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
FPC_BIN=$(printenv FPC || echo fpc)
for tool in "$FPC_BIN" timeout cmp objdump readelf mktemp awk grep; do
  command -v "$tool" >/dev/null || { echo "D12-НУЛЬ-БЛОК: $tool" >&2; exit 127; }
done
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = \
    2c498b35af53c085450eac6f51b87facf7f9aa47
fi
# Тільки D1: один результат із однією pinned людською проєкцією.
normal_repl() {
  awk '
    {
      sub(/\r$/, ""); sub(/[ \t]+$/, "");
      line=$0; sub(/^sens\[укр\]> /, "", line);
      if (line ~ /(ПОМИЛКА|помилка|ERROR|Error|error)/) bad=1;
      if (line ~ /^\([ \t]*т[ \t]+а[ \t]+к[ \t]*\)$/) line="ТАК";
      if (line ~ /^\([ \t]*н[ \t]+і[ \t]*\)$/) line="НІ";
      if (line=="1") line="ТАК";
      if (line=="0") line="НІ";
      if (line=="ТАК" || line=="НІ") { print line; n++ }
    }
    END { if (bad || n!=1) exit 48 }
  ' "$1"
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for entry in \
  'scripts/test-elfd12addzero-fixtures.pas test-elfd12addzero-fixtures' \
  'src/sensd12addzero-elf.lpr sensd12addzero-elf'; do
  read -r path exe <<< "$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$path" > "$TMP/$exe.build.out" 2> "$TMP/$exe.build.err"; then
    cat "$TMP/$exe.build.out" "$TMP/$exe.build.err" >&2
    exit 1
  fi
  test -x "$TMP/bin/$exe"
done
timeout 15s "$TMP/bin/test-elfd12addzero-fixtures" "$TMP/physical" \
  > "$TMP/cases.tsv" 2> "$TMP/fixtures.err"
if ! grep -Fq 'D12-ДОДАТИ-НУЛЬ-СВІДКИ-ГАРАЗД випадків=14' "$TMP/fixtures.err"; then
  cat "$TMP/fixtures.err" >&2; exit 1
fi
test "$(wc -l < "$TMP/cases.tsv")" -eq 14
CLI="$TMP/bin/sensd12addzero-elf"
MODE=--додати-нуль-D12
PASS=0; YES=0; NO=0; ORACLE=0
while IFS=$'\t' read -r label a b truth; do
  test -n "$label"
  [[ "$truth" == 0 || "$truth" == 1 ]]
  timeout 15s "$CLI" "$MODE" \
    "$TMP/physical/$label-a.sens" "$TMP/physical/$label-b.sens" \
    "$TMP/$label.elf" > "$TMP/compiler.out" 2> "$TMP/compiler.err"
  test ! -s "$TMP/compiler.err"
  grep -Fq 'D12-ОДИН-ELF-НУЛЬ-ГОТОВО' "$TMP/compiler.out"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  tail -c +121 "$TMP/$label.elf" > "$TMP/$label.code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" \
    > "$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'test[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'sete[[:space:]]+al' "$TMP/$label.dis"
  grep -Eiq 'movzx[[:space:]]+eax,' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" > "$TMP/$label.actual.sens"
  cmp "$TMP/physical/$label-expected.sens" "$TMP/$label.actual.sens"
  if [[ "$truth" == 1 ]]; then YES=$((YES+1)); else NO=$((NO+1)); fi
  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    printf '(нуль? (додати %s %s))\n' "$a" "$b" \
      > "$TMP/$label.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.oracle.lisp" \
      > "$TMP/$label.oracle" 2> "$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    normal_repl "$TMP/$label.oracle" > "$TMP/$label.normal" || {
      cat "$TMP/$label.oracle" >&2; exit 1;
    }
    if [[ "$truth" == 1 ]]; then printf 'ТАК\n' > "$TMP/$label.wanted"
    else printf 'НІ\n' > "$TMP/$label.wanted"; fi
    cmp "$TMP/$label.wanted" "$TMP/$label.normal" || {
      cat "$TMP/$label.oracle" >&2; exit 1;
    }
    ORACLE=$((ORACLE+1))
  fi
  PASS=$((PASS+1))
done < "$TMP/cases.tsv"
test "$PASS" -eq 14
test "$YES" -gt 0 && test "$NO" -gt 0
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  test "$ORACLE" -eq 14
fi
NEG=0
reject() {
  local label=$1; shift
  local status=0
  timeout 15s "$CLI" "$@" "$TMP/reject-$label.elf" \
    > "$TMP/reject.out" 2> "$TMP/reject.err" || status=$?
  test "$status" -ne 0 && test "$status" -ne 124
  test ! -e "$TMP/reject-$label.elf"
  test ! -s "$TMP/reject.out"
  grep -Fq 'D12-ОДИН-ELF-НУЛЬ-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
reject plus "$MODE" "$TMP/physical/overflow-up.sens" "$TMP/physical/one.sens"
reject minus "$MODE" "$TMP/physical/overflow-down.sens" "$TMP/physical/minus-one.sens"
reject d1 "$MODE" "$TMP/physical/bad-d1.sens" "$TMP/physical/01-b.sens"
reject d7 "$MODE" "$TMP/physical/bad-d7.sens" "$TMP/physical/01-b.sens"
reject d24 "$MODE" "$TMP/physical/01-a.sens" "$TMP/physical/bad-d24.sens"
reject corrupt "$MODE" "$TMP/physical/corrupt.sens" "$TMP/physical/01-b.sens"
reject empty "$MODE" "$TMP/physical/empty.sens" "$TMP/physical/01-b.sens"
reject lisp "$MODE" "$TMP/physical/fake.lisp" "$TMP/physical/01-b.sens"
reject missing "$MODE" "$TMP/physical/missing.sens" "$TMP/physical/01-b.sens"
reject mode --вигаданий "$TMP/physical/01-a.sens" "$TMP/physical/01-b.sens"
test "$NEG" -eq 10
# Публікація не може перезаписати ані inode, ані символічне посилання.
cp "$TMP/01.elf" "$TMP/occupied.elf"
status=0
timeout 15s "$CLI" "$MODE" "$TMP/physical/01-a.sens" \
  "$TMP/physical/01-b.sens" "$TMP/occupied.elf" \
  > "$TMP/occupied.out" 2> "$TMP/occupied.err" || status=$?
test "$status" -ne 0; test ! -s "$TMP/occupied.out"
cmp "$TMP/01.elf" "$TMP/occupied.elf"
ln -s "$TMP/01.elf" "$TMP/occupied-link.elf"
status=0
timeout 15s "$CLI" "$MODE" "$TMP/physical/01-a.sens" \
  "$TMP/physical/01-b.sens" "$TMP/occupied-link.elf" \
  > "$TMP/link.out" 2> "$TMP/link.err" || status=$?
test "$status" -ne 0
test -L "$TMP/occupied-link.elf"; test ! -s "$TMP/link.out"
timeout 15s "$CLI" "$MODE" "$TMP/physical/01-a.sens" \
  "$TMP/physical/01-b.sens" "$TMP/rebuilt.elf" > /dev/null
cmp "$TMP/01.elf" "$TMP/rebuilt.elf"
timeout 5s "$TMP/rebuilt.elf" > "$TMP/rebuilt.sens"
cmp "$TMP/physical/01-expected.sens" "$TMP/rebuilt.sens"
echo "D12-ДОДАТИ-НУЛЬ-ГАРАЗД фізичних=$PASS істина=$YES хиба=$NO oracle=$ORACLE негативів=$NEG ELF=ADD,TEST,SETE,MOVZX вихід=D1-T5M RAPL=НЕ-ВИМІРЯНО"
