#!/usr/bin/env bash
# G6.98: незалежні 256 реальних ELF64 та byte-exact T5M.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЕЛФ-Д12-МАТРИЦЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN="${FPC:-fpc}"
for exe in "$FPC_BIN" timeout cmp mktemp readelf seq wc; do
  command -v "$exe" >/dev/null || {
    echo "ЕЛФ-Д12-МАТРИЦЯ-БЛОК: відсутній $exe" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP="$(mktemp -d)"
trap 'status=$?; if (( status != 0 )); then
  echo "ЕЛФ-Д12-МАТРИЦЯ-ВІДМОВА: код=$status рядок=$LINENO" >&2;
  for log in "$TMP"/*.err "$TMP"/*.log; do
    [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 30 "$log" >&2; }
  done;
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/дані" "$TMP/ельф"
# Компілюємо дійсний FPC backend, а не модель на іншій мові.
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd12elf "$ROOT/src/sensd12elf.lpr" >"$TMP/fpc-cli.log" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-shyroka-matrytsia \
  "$ROOT/scripts/test-elfd12add-shyroka-matrytsia.pas" \
  >"$TMP/fpc-test.log" 2>&1
timeout 30s "$TMP/bin/test-shyroka-matrytsia" "$TMP/дані" \
  >"$TMP/generator.log"
grep -Fq 'випадків=256 крайових=16' "$TMP/generator.log"
COUNT=0
REPEATED=0
for index in $(seq -w 0 255); do
  key="$(printf '%04d' "$((10#$index))")"
  left="$TMP/дані/$key-l.sens"
  right="$TMP/дані/$key-r.sens"
  expected="$TMP/дані/$key-expected.sens"
  image="$TMP/ельф/$key.elf"
  test "$(wc -c <"$left")" -eq 3
  test "$(wc -c <"$right")" -eq 3
  test "$(wc -c <"$expected")" -eq 3
  timeout 10s "$TMP/bin/sensd12elf" --додати-D12 "$left" "$right" "$image" \
    >"$TMP/compile.out" 2>"$TMP/compile.err"
  test -x "$image" && test ! -s "$TMP/compile.err"
  grep -Fq 'machine-add=1' "$TMP/compile.out"
  timeout 5s "$image" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp -s "$TMP/actual.sens" "$expected" || {
    echo "ЕЛФ-Д12-МАТРИЦЯ-РОЗБІЖНІСТЬ: випадок=$key" >&2; exit 1;
  }
  if (( COUNT < 16 )); then
    timeout 5s readelf -h "$image" >"$TMP/elfheader.log"
    grep -Eq 'Type:.*DYN' "$TMP/elfheader.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elfheader.log"
    timeout 10s "$TMP/bin/sensd12elf" --додати-D12 "$left" "$right" \
      "$TMP/ельф/$key-повтор.elf" >"$TMP/repeat.out" 2>"$TMP/repeat.err"
    test ! -s "$TMP/repeat.err"
    cmp "$image" "$TMP/ельф/$key-повтор.elf"
    REPEATED=$((REPEATED+1))
  fi
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 256 && test "$REPEATED" -eq 16
# Контрольні незалежні семантичні форми виконує pinned SENS REPL
# в окремому чинному scripts/test-elfd12add.sh.
echo 'ЕЛФ-Д12-ШИРОКА-МАТРИЦЯ-ГАРАЗД FPC=реальний ELF64=256 T5M-cmp=256 повтор-ELF=16 energy=NOT-MEASURED'
