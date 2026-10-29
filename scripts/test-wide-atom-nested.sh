#!/usr/bin/env bash
# G6.150 — інтеграція злитого pinned WideIR і атомарного каталогу,
# 8 лівих + 8 правих реальних D5 ELF, без власної семантики.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for tool in fpc git timeout cmp readelf grep mktemp find;do command -v "$tool" >/dev/null;done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
bash scripts/check-pin.sh; bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
finish() {
  local rc=$?
  if ((rc));then
    echo "АТОМ-ПАКЕТ-D5-ВІДМОВА rc=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err;do
      if [[ -s "$f" ]];then tail -n 12 "$f" >&2;fi
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP"/{bin,units,left,right,inputs,single}
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1";then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1"
  fi
}
for row in \
  'scripts/test-irarithchain.pas test-irarithchain' \
  'scripts/test-irarithpravy.pas test-irarithpravy' \
  'src/senswideatompaketelf.lpr senswideatompaketelf' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senschyslo.lpr senschyslo';do
  read -r file binary <<<"$row"
  timeout 180s "$(printenv FPC || echo fpc)" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$file" >"$TMP/$binary.build.log" 2>&1 || {
      cat "$TMP/$binary.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 140s "$TMP/bin/test-irarithchain" "$TMP/left" \
  >"$TMP/left.gen.log" 2>"$TMP/left.gen.err"
grep -Fxq 'D5-ARITH-CHAIN-UNIT-OK positive=71 negative=24' "$TMP/left.gen.log"
check_heap "$TMP/left.gen.err"
timeout 140s "$TMP/bin/test-irarithpravy" "$TMP/right" \
  >"$TMP/right.gen.log" 2>"$TMP/right.gen.err"
grep -Fxq 'G6.141-RIGHT-D5-UNIT-OK positive=36 negative=16' "$TMP/right.gen.log"
check_heap "$TMP/right.gen.err"
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 ]];then test -n "$ORACLE";fi
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE";test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
INPUTS=();ORACLE_COUNT=0
for side in left right;do
  if [[ "$side" == left ]];then
    depths=(2 3 4 5 8 16 50 100)
  else
    depths=(2 3 4 5 6 7 8 16)
  fi
  for depth in "${depths[@]}";do
    idx=2
    if [[ "$side" == left && "$depth" -gt 16 ]];then idx=1;fi
    label="$side-$depth"
    cp "$TMP/$side/$depth-$idx.sens" "$TMP/inputs/$label.sens"
    cp "$TMP/$side/$depth-$idx.expected.sens" "$TMP/inputs/$label.expected.sens"
    input="$TMP/inputs/$label.sens"
    INPUTS+=("$input")
    timeout 40s "$TMP/bin/senswidefrontelf" \
      --скомпілювати-фізичну-форму "$input" "$TMP/single/$label.elf" \
      >"$TMP/front.out" 2>"$TMP/front.err"
    check_heap "$TMP/front.err"
    if [[ -n "$ORACLE" ]];then
      # Повна українська проєкція тут тільки для незалежного SENS REPL.
      if [[ "$side" == left ]];then
        if ((depth>16));then nested=-5;else nested=0;fi
        right=(3 -7 11 -2)
        for ((i=0;i<depth;i++));do
          if ((i%2==0));then
            nested="(відняти $nested ${right[i%4]})"
          else
            nested="(додати $nested ${right[i%4]})"
          fi
        done
      else
        nested=0
        lefts=(3 -7 11 -2)
        for ((i=depth-1;i>=0;i--));do
          if ((i%2==0));then
            nested="(додати ${lefts[i%4]} $nested)"
          else
            nested="(відняти ${lefts[i%4]} $nested)"
          fi
        done
      fi
      printf '%s\n' "$nested" >"$TMP/oracle.lisp"
      timeout 60s "$ORACLE" "$TMP/oracle.lisp" \
        >"$TMP/oracle.out" 2>"$TMP/oracle.err"
      test ! -s "$TMP/oracle.err"
      timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
        "$TMP/inputs/$label.expected.sens" >"$TMP/machine.ukr"
      cmp "$TMP/oracle.out" "$TMP/machine.ukr"
      ORACLE_COUNT=$((ORACLE_COUNT+1))
    fi
  done
done
test "${#INPUTS[@]}" -eq 16
MODE=--скомпілювати-атомарний-пакет
timeout 240s "$TMP/bin/senswideatompaketelf" "$MODE" "$TMP/published" \
  "${INPUTS[@]}" >"$TMP/package.log" 2>"$TMP/package.err"
check_heap "$TMP/package.err"
grep -Fq 'АТОМ-ПАКЕТ-ГОТОВО: фізичних-ELF=16' "$TMP/package.log"
test "$(find "$TMP/published" -maxdepth 1 -type f -name '*.elf' | wc -l)" -eq 16
COUNT=0
for input in "${INPUTS[@]}";do
  label="${input##*/}";label="${label%.sens}"
  elf="$TMP/published/$label.elf"
  test -x "$elf"
  cmp "$TMP/single/$label.elf" "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  if readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'заборонено динамічний ELF' >&2;exit 1
  fi
  timeout 5s "$elf" >"$TMP/actual.sens" 2>"$TMP/execution.err"
  test ! -s "$TMP/execution.err"
  cmp "$TMP/inputs/$label.expected.sens" "$TMP/actual.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 3
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 16
if [[ -n "$ORACLE" ]];then test "$ORACLE_COUNT" -eq 16;fi
test "$(find "$TMP" -maxdepth 1 -name '.senpak*' | wc -l)" -eq 0
NEG=0
reject() {
  local kind="$1";shift
  local target="$1";shift
  local rc=0
  timeout 120s "$TMP/bin/senswideatompaketelf" "$MODE" "$target" "$@" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  if [[ "$rc" -ne 2 || -s "$TMP/reject.out" ]];then
    echo "неправомірно прийнято $kind rc=$rc" >&2;exit 1
  fi
  test -s "$TMP/reject.err"
  check_heap "$TMP/reject.err"
  test "$(find "$TMP" -maxdepth 1 -name '.senpak*' | wc -l)" -eq 0
  NEG=$((NEG+1))
}
printf '\xff' >"$TMP/inputs/bad.sens"
reject late-invalid "$TMP/failed-late" \
  "${INPUTS[@]:0:15}" "$TMP/inputs/bad.sens"
test ! -e "$TMP/failed-late"
reject occupied "$TMP/published" "${INPUTS[@]}"
test "$(find "$TMP/published" -maxdepth 1 -name '*.elf' | wc -l)" -eq 16
reject duplicate "$TMP/duplicate" "${INPUTS[0]}" "${INPUTS[0]}"
test ! -e "$TMP/duplicate"
reject overlimit "$TMP/overlimit" "${INPUTS[@]}" "${INPUTS[0]}"
test ! -e "$TMP/overlimit"
cp "${INPUTS[0]}" "$TMP/inputs/text.lisp"
reject projection "$TMP/projection" "$TMP/inputs/text.lisp"
test ! -e "$TMP/projection"
reject missing "$TMP/missing-output" "$TMP/inputs/absent.sens"
test ! -e "$TMP/missing-output"
ln -s "$TMP/absent-target" "$TMP/dangling"
reject symlink "$TMP/dangling" "${INPUTS[1]}"
test -L "$TMP/dangling" && test ! -e "$TMP/absent-target"
reject no-parent "$TMP/no-parent/final" "${INPUTS[1]}"
test ! -e "$TMP/no-parent"
test "$NEG" -eq 8
timeout 240s "$TMP/bin/senswideatompaketelf" "$MODE" "$TMP/recovered" \
  "${INPUTS[@]}" >"$TMP/recovered.log" 2>"$TMP/recovered.err"
check_heap "$TMP/recovered.err"
test "$(find "$TMP/recovered" -maxdepth 1 -name '*.elf' | wc -l)" -eq 16
for input in "${INPUTS[@]}";do
  label="${input##*/}";label="${label%.sens}"
  cmp "$TMP/published/$label.elf" "$TMP/recovered/$label.elf"
done
echo "G6.150-ATOM-NESTED-D5-OK left=8 right=8 native=16 exactELF=16 exactT5M=16 negative=$NEG oracle=$ORACLE_COUNT recovered=16 energy=NOT_MEASURED"
