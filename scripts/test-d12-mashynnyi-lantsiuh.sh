#!/usr/bin/env bash
# G6.77 — перевірка двох фізичних x86-64 машин без текстового проміжного шляху.
# Результат SUB ELF (.sens) напряму стає вхідним .sens компілятора ADD.
# Це тест механізмів; мовний закон визначає тільки pinned SENS Contract 12.
set -Eeuo pipefail
trap 'echo "D12-ЛАНЦЮГ-ПОМИЛКА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-ЛАНЦЮГ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc git readelf timeout cmp mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "D12-ЛАНЦЮГ-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'D12-ЛАНЦЮГ-БЛОК: немає незалежного pinned SENS REPL' >&2; exit 127;
}
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/d12-lantsiuh/units"
BIN="$ROOT/build/m0.2/d12-lantsiuh/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
# Створені програми FPC: лише наявний pinned числовий codec і два емітери.
for row in \
  'src/senschyslo.lpr senschyslo' \
  'src/sensd12sub-elf.lpr sensd12sub-elf' \
  'src/sensd12elf.lpr sensd12elf'; do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.build.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.build.err" >&2; exit 1;
    }
done

# input.lisp — тільки явна українська людська числова проєкція;
# результат --з-укр — точний packed D12 .sens, не додатковий opcode.
mint_d12() {
  local decimal=$1 stem=$2
  printf '%s\n' "$decimal" >"$TMP/$stem.lisp"
  timeout 10s "$BIN/senschyslo" --з-укр D12 \
    "$TMP/$stem.lisp" "$TMP/$stem.sens" >"$TMP/$stem.mint.out"
  test ! -s "$TMP/$stem.mint.out"
  test -s "$TMP/$stem.sens"
}
check_oracle() {
  local tag=$1 operation=$2 left=$3 right=$4 result_file=$5 width=$6
  printf '(%s %s %s)\n' "$operation" "$left" "$right" >"$TMP/$tag-expr.lisp"
  timeout 60s "$ORACLE" "$TMP/$tag-expr.lisp" \
    >"$TMP/$tag-oracle.out" 2>"$TMP/$tag-oracle.err" || {
      cat "$TMP/$tag-oracle.err" >&2; exit 1;
    }
  test ! -s "$TMP/$tag-oracle.err"
  timeout 10s "$BIN/senschyslo" --в-укр "D$width" "$result_file" \
    >"$TMP/$tag-machine-ukr.out"
  cmp "$TMP/$tag-oracle.out" "$TMP/$tag-machine-ukr.out"
}
check_elf() {
  local elf=$1 output=$2
  test -x "$elf"
  readelf -h "$elf" | grep -Eq 'Type:[[:space:]]+DYN'
  timeout 5s "$elf" >"$output"
  test -s "$output"
}
reject_add() {
  local label=$1 first=$2 second=$3
  local target="$TMP/$label-denied.elf"
  if timeout 10s "$BIN/sensd12elf" --додати-D12 "$first" "$second" "$target" \
    >"$TMP/$label-denied.out" 2>"$TMP/$label-denied.err"; then
    echo "D12-ЛАНЦЮГ-ПРОВАЛ: невірний вхід прийнято ($label)" >&2; exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/$label-denied.out"
  grep -Fq 'ELF-D12-' "$TMP/$label-denied.err"
}
EXECUTED=0
PARITY=0
# Вісім невигаданих знакових пар, включно з обома краями D12.
for row in \
  '01:31:42' '02:-7:7' '03:2046:-1' '04:-2047:1' \
  '05:0:0' '06:90:-90' '07:5:5' '08:0:-1'; do
  IFS=: read -r label a b <<< "$row"
  mint_d12 "$a" "$label-a"
  mint_d12 "$b" "$label-b"
  timeout 10s "$BIN/sensd12sub-elf" --віднімати-D12 \
    "$TMP/$label-a.sens" "$TMP/$label-b.sens" "$TMP/$label-sub.elf" \
    >"$TMP/$label-sub.publish" 2>"$TMP/$label-sub.publish.err"
  check_elf "$TMP/$label-sub.elf" "$TMP/$label-sub.sens"
  EXECUTED=$((EXECUTED+1))
  check_oracle "$label-sub" відняти "$a" "$b" "$TMP/$label-sub.sens" 12
  PARITY=$((PARITY+1))
  # Фізичний вихід попереднього ELF — БЕЗ decode/re-encode на вході ADD.
  timeout 10s "$BIN/sensd12elf" --додати-D12 \
    "$TMP/$label-sub.sens" "$TMP/$label-b.sens" "$TMP/$label-add.elf" \
    >"$TMP/$label-add.publish" 2>"$TMP/$label-add.publish.err"
  check_elf "$TMP/$label-add.elf" "$TMP/$label-add.sens"
  cmp "$TMP/$label-a.sens" "$TMP/$label-add.sens"
  EXECUTED=$((EXECUTED+1))
  read -r intermediate <"$TMP/$label-sub-machine-ukr.out"
  check_oracle "$label-add" додати "$intermediate" "$b" "$TMP/$label-add.sens" 12
  PARITY=$((PARITY+1))
done

# Дві машини мають РІЗНІ межі: SUB підтримує D24 результат;
# звичайний ADD не приймає D24 як операнд без явного профілю.
REJECTED=0
for row in 'upper:2047:-1' 'lower:-2048:1'; do
  IFS=: read -r label a b <<< "$row"
  mint_d12 "$a" "$label-a"
  mint_d12 "$b" "$label-b"
  timeout 10s "$BIN/sensd12sub-elf" --віднімати-D12 \
    "$TMP/$label-a.sens" "$TMP/$label-b.sens" "$TMP/$label-sub.elf" \
    >"$TMP/$label-sub.publish"
  check_elf "$TMP/$label-sub.elf" "$TMP/$label-sub.sens"
  EXECUTED=$((EXECUTED+1))
  check_oracle "$label-sub" відняти "$a" "$b" "$TMP/$label-sub.sens" 24
  PARITY=$((PARITY+1))
  reject_add "$label" "$TMP/$label-sub.sens" "$TMP/$label-b.sens"
  REJECTED=$((REJECTED+1))
done
printf '\377' >"$TMP/corrupt.sens"
reject_add corrupt "$TMP/corrupt.sens" "$TMP/01-b.sens"
REJECTED=$((REJECTED+1))
test "$EXECUTED" -eq 18
test "$PARITY" -eq 18
test "$REJECTED" -eq 3
echo "D12-ЛАНЦЮГ-ГАРАЗД машинних-ELF=$EXECUTED pinned-SENS=$PARITY негативів=$REJECTED фізичний-проміжний=T5M без-текстового-мосту=так енергія=не-виміряна"
