#!/usr/bin/env bash
# G6.93 — фізична D6 вкладеність 1..5 → один ELF з N машинними ADD.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd);cd "$ROOT"
trap 'echo "D6-ВКЛАДЕННЯ-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
for tool in git fpc timeout readelf objdump cmp mktemp grep dd;do
  command -v "$tool" >/dev/null || { echo "потрібен $tool" >&2;exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'потрібен Linux x86-64' >&2;exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
git -C sens-oracle show HEAD:lib/domains/d6.lisp |
  grep -Fq '(001110 (ук додати-1) (укр додати-1)'
git -C sens-oracle show HEAD:lib/machine/profile/current-domain-x86-64.lisp |
  grep -Fq 'домен-шостий додати-1 fast-path "ADD /'
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'не знайдено незалежний pinned SENS' >&2;exit 127;
}
TMP=$(mktemp -d);trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/irnestedstep/units"
BIN="$ROOT/build/m0.2/irnestedstep/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for row in   'scripts/test-irnestedstep.pas test-irnestedstep'   'src/sensnestedstepelf.lpr sensnestedstepelf'   'src/senschyslo.lpr senschyslo';do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2;exit 1;
    }
done
if ! timeout 90s "$BIN/test-irnestedstep" "$TMP" >"$TMP/unit.out" 2>"$TMP/unit.err";then
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1
fi
grep -Fxq 'D6-NESTED-UNIT-OK positive=20 negative=14' "$TMP/unit.out" || {
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1;
}
COUNT=0
for depth in 1 2 3 4 5;do
  for entry in '0:-2048' '1:-1' '2:0' '3:2040';do
    IFS=: read -r idx number <<< "$entry"
    tag="$depth-$idx"
    INPUT="$TMP/$tag.sens";EXE="$TMP/$tag.elf"
    test -s "$INPUT" && test -s "$EXE"
    chmod 500 "$EXE"
    readelf -h "$EXE" | grep -Eq 'Type:[[:space:]]+DYN'
    if readelf -l "$EXE" | grep -Eq 'INTERP|DYNAMIC';then
      echo 'ELF має неприпустимий loader' >&2;exit 1;
    fi
    timeout 5s "$EXE" >"$TMP/$tag.machine.sens" 2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    cmp "$TMP/$tag.expected.sens" "$TMP/$tag.machine.sens"
    test "$(wc -c <"$TMP/$tag.machine.sens")" -eq 3
    timeout 10s "$BIN/sensnestedstepelf" --вкладене-додавання-D6 \
      "$INPUT" "$TMP/$tag.cli.elf" >"$TMP/$tag.cli.out" \
      2>"$TMP/$tag.cli.err"
    grep -Fq '0 unfreed memory blocks' "$TMP/$tag.cli.err"
    cmp "$EXE" "$TMP/$tag.cli.elf"
    grep -Fq 'D6-NESTED-ELF64' "$TMP/$tag.cli.out"
    # Пролог точно MOV(5)+N*ADD(5). Не шукаємо випадкові opcode у таблицях.
    dd if="$EXE" of="$TMP/$tag.prefix" bs=1 skip=120 \
      count=$((5+depth*5)) status=none
    objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.prefix" \
      >"$TMP/$tag.dis"
    test "$(grep -Eic 'add[[:space:]]+eax,' "$TMP/$tag.dis")" -eq "$depth"
    nested="$number"
    for ((z=0;z<depth;z++));do nested="(додати-1 $nested)";done
    printf '%s\n' "$nested" >"$TMP/$tag.oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.oracle.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err" || {
        cat "$TMP/$tag.oracle.err" >&2;exit 1;
      }
    test ! -s "$TMP/$tag.oracle.err"
    timeout 10s "$BIN/senschyslo" --в-укр D12 \
      "$TMP/$tag.machine.sens" >"$TMP/$tag.machine.ukr"
    cmp "$TMP/$tag.oracle.out" "$TMP/$tag.machine.ukr"
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 20
cp "$TMP/1-2.elf" "$TMP/occupied.elf"
if timeout 10s "$BIN/sensnestedstepelf" --вкладене-додавання-D6 \
  "$TMP/1-2.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err";then
  echo 'помилковий перезапис ELF' >&2;exit 1;
fi
test ! -s "$TMP/occupied.out" && test -s "$TMP/occupied.err"
cmp "$TMP/occupied.elf" "$TMP/1-2.elf"
cp "$TMP/1-2.sens" "$TMP/projection.lisp"
if timeout 10s "$BIN/sensnestedstepelf" --вкладене-додавання-D6 \
    "$TMP/projection.lisp" "$TMP/forbidden.elf" \
    >"$TMP/projection.out" 2>"$TMP/projection.err";then
  echo 'помилково прийнято .lisp' >&2;exit 1;
fi
test ! -e "$TMP/forbidden.elf" && test ! -s "$TMP/projection.out"
echo "D6-ВКЛАДЕННЯ-ELF-ГАРАЗД physical=20 oracle=20 negative=14 machine-add-depth=1..5 no-clobber=yes energy=NOT-MEASURED"
