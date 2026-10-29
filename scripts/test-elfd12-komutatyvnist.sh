#!/usr/bin/env bash
# G6.68 — перестановка двох точних числових операндів у двох нативних ELF.
# Джерело числових законів — pinned SENS; тут тільки механічні свідки.
set -Eeuo pipefail
trap 'echo "D12-ПЕРЕСТАНОВКА-ВІДМОВА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'D12-ПЕРЕСТАНОВКА-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for exe in fpc cmp timeout readelf grep mktemp; do
  command -v "$exe" >/dev/null || { echo "D12-ПЕРЕСТАНОВКА-БЛОК: немає $exe" >&2; exit 127; }
done
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "${SENS_ORACLE_BIN:-}" ]]; then
  echo 'D12-ПЕРЕСТАНОВКА-БЛОК: обовʼязковий незалежний pinned SENS REPL' >&2; exit 127
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/d12-perestanovka/units"
BIN="$ROOT/build/m0.2/d12-perestanovka/bin"
mkdir -p "$UNITS" "$BIN" "$TMP/add" "$TMP/mul"
FPC_BIN=${FPC:-fpc}
for source in src/sensd12elf.lpr src/sensd12mul-elf.lpr scripts/test-elfd12add.pas scripts/test-elfd12mul-fixtures.pas src/senschyslo.lpr; do
  name=$(basename "$source")
  name=${name%.*}
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -o"$name" "$ROOT/$source" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
    cat "$TMP/$name.build" "$TMP/$name.err" >&2; exit 1;
  }
done
timeout 20s "$BIN/test-elfd12add" "$TMP/add" >"$TMP/add-fixtures.out"
timeout 20s "$BIN/test-elfd12mul-fixtures" "$TMP/mul" >"$TMP/mul-fixtures.out" 2>"$TMP/mul-fixtures.err"
grep -Fq 'D12-MUL-UNIT-NEGATIVE-OK cases=3' "$TMP/mul-fixtures.err"

# Кожна пара: фізичні вхідні слова, канонічний результат, два реальні ELF.
MACHINE=0
ORACLE=0
for vector in 'add:02:31:42:12' 'add:03:-12:7:12' 'add:05:-2048:2047:12' 'mul:negative:7:-7:12' 'mul:widened:-2048:-1:24' 'mul:positive:12:12:12'; do
  IFS=: read -r operation label left right width <<< "$vector"
  if [[ "$operation" == add ]]; then
    left_file="$TMP/add/$label-l.sens"
    right_file="$TMP/add/$label-r.sens"
    expected="$TMP/add/$label-expected.sens"
    cli="$BIN/sensd12elf"
    mode='--додати-D12'
    surface='додати'
  else
    left_file="$TMP/mul/$label-a.sens"
    right_file="$TMP/mul/$label-b.sens"
    expected="$TMP/mul/$label-expected.sens"
    cli="$BIN/sensd12mul-elf"
    mode='--помножити-D12'
    surface='помножити'
  fi
  for orientation in direct reverse; do
    if [[ "$orientation" == direct ]]; then
      one="$left_file"; two="$right_file"; x="$left"; y="$right"
    else
      one="$right_file"; two="$left_file"; x="$right"; y="$left"
    fi
    elf="$TMP/$operation-$label-$orientation.elf"
    output="$TMP/$operation-$label-$orientation.sens"
    timeout 15s "$cli" "$mode" "$one" "$two" "$elf" >"$TMP/publish.out" 2>"$TMP/publish.err"
    test -x "$elf"
    readelf -h "$elf" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)'
    timeout 5s "$elf" >"$output"
    test -s "$output"
    cmp "$expected" "$output"
    MACHINE=$((MACHINE+1))
    # Оракул читає лише повну українську людську проєкцію; порівнюємо
    # її з окремо виведеною проєкцією РЕАЛЬНОГО машинного T5M.
    if [[ -n "${SENS_ORACLE_BIN:-}" && ( "$label" == 02 || "$label" == 03 || "$label" == negative || "$label" == widened ) ]]; then
      printf '(%s %s %s)\n' "$surface" "$x" "$y" >"$TMP/oracle-input.lisp"
      timeout 60s "$SENS_ORACLE_BIN" "$TMP/oracle-input.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err"
      test ! -s "$TMP/oracle.err"
      timeout 10s "$BIN/senschyslo" --в-укр "D$width" "$output" >"$TMP/machine-ukr.out"
      cmp "$TMP/oracle.out" "$TMP/machine-ukr.out"
      ORACLE=$((ORACLE+1))
    fi
  done
  cmp "$TMP/$operation-$label-direct.sens" "$TMP/$operation-$label-reverse.sens"
done
test "$MACHINE" -eq 12
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then test "$ORACLE" -eq 8; fi

# ADD ще не допускає D12→D24. Перестановка НЕ повинна обходити цю межу.
NEGATIVE=0
for orientation in direct reverse; do
  if [[ "$orientation" == direct ]]; then
    one="$TMP/add/overplus-l.sens"; two="$TMP/add/overplus-r.sens"
  else
    one="$TMP/add/overplus-r.sens"; two="$TMP/add/overplus-l.sens"
  fi
  target="$TMP/overflow-$orientation.elf"
  if timeout 10s "$BIN/sensd12elf" --додати-D12 "$one" "$two" "$target" >"$TMP/reject.out" 2>"$TMP/reject.err"; then
    echo 'D12-ПЕРЕСТАНОВКА-ПОМИЛКА: переповнення помилково прийняте' >&2; exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ELF-D12-' "$TMP/reject.err"
  NEGATIVE=$((NEGATIVE+1))
done
echo "D12-ПЕРЕСТАНОВКА-ГАРАЗД виконаних-ELF=$MACHINE pinned-REPL=$ORACLE негативів=$NEGATIVE D12-до-D24=різні-межі енергія=не-виміряна"
