#!/usr/bin/env bash
# G6.97 / G6.137 / G6.138 — реальні ELF 1..16/50/100 змішаних ADD/SUB з фізичного D5 дерева.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
trap 'echo "D5-ЛАНЦЮГ-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
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
git -C sens-oracle show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01010 (ук додати) (укр додати)'
git -C sens-oracle show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01011 (ук відняти) (укр відняти)'
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'не знайдено pinned незалежний SENS REPL' >&2;exit 127;
}
TMP=$(mktemp -d);trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/irarithchain/units"
BIN="$ROOT/build/m0.2/irarithchain/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-irarithchain.pas test-irarithchain' \
  'src/sensarithchainelf.lpr sensarithchainelf' \
  'src/senschyslo.lpr senschyslo';do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2;exit 1;
    }
done
if ! timeout 90s "$BIN/test-irarithchain" "$TMP" >"$TMP/unit.out" 2>"$TMP/unit.err";then
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1
fi
grep -Fxq 'D5-ARITH-CHAIN-UNIT-OK positive=71 negative=24' "$TMP/unit.out" || {
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1;
}
COUNT=0
for depth in $(seq 1 16) 50 100;do
  for row in '0:-2000' '1:-5' '2:0' '3:2040' '4:-1473';do
    IFS=: read -r idx base <<< "$row"
    if ((depth>16 && idx==0));then continue;fi
    if ((idx==4 && depth!=100));then continue;fi
    # Зберігаємо старі чотири основи для 1..8; на 9..16
    # -2000 переповнювало б signed D12, це окремий негатив.
    if ((depth>8 && idx==0));then base=-1900;fi
    tag="$depth-$idx"
    EXE="$TMP/$tag.elf"
    chmod 500 "$EXE"
    readelf -h "$EXE" | grep -Eq 'Type:[[:space:]]+DYN'
    if readelf -l "$EXE" | grep -Eq 'INTERP|DYNAMIC';then
      echo 'ELF не повинен мати динамічних залежностей' >&2;exit 1;
    fi
    timeout 5s "$EXE" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.err"
    test ! -s "$TMP/$tag.err"
    cmp "$TMP/$tag.expected.sens" "$TMP/$tag.actual.sens"
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
    timeout 10s "$BIN/sensarithchainelf" --ланцюг-D5 \
      "$TMP/$tag.sens" "$TMP/$tag.cli.elf" \
      >"$TMP/$tag.cli.out" 2>"$TMP/$tag.cli.err"
    grep -Fq '0 unfreed memory blocks' "$TMP/$tag.cli.err"
    cmp "$EXE" "$TMP/$tag.cli.elf"
    grep -Fq 'D5-ARITH-CHAIN-ELF64' "$TMP/$tag.cli.out"
    dd if="$EXE" of="$TMP/$tag.prefix" bs=1 skip=120 \
      count=$((5+5*depth)) status=none
    objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.prefix" \
      >"$TMP/$tag.dis"
    grep -Eio '(add|sub)[[:space:]]+eax,' "$TMP/$tag.dis" |
      awk '{print $1}' >"$TMP/$tag.actual.ops"
    : >"$TMP/$tag.expected.ops"
    nested="$base"
    # Точні D12 праві атоми повторюються кожні чотири кроки;
    # жоден із N=16 кроків не пропускається в незалежному оракулі.
    rights=(3 -7 11 -2)
    for ((z=0;z<depth;z++));do
      if ((z%2==0));then
        printf 'sub\n' >>"$TMP/$tag.expected.ops"
        nested="(відняти $nested ${rights[z%4]})"
      else
        printf 'add\n' >>"$TMP/$tag.expected.ops"
        nested="(додати $nested ${rights[z%4]})"
      fi
    done
    cmp "$TMP/$tag.expected.ops" "$TMP/$tag.actual.ops"
    printf '%s\n' "$nested" >"$TMP/$tag.oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.oracle.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err" || {
        cat "$TMP/$tag.oracle.err" >&2;exit 1;
      }
    test ! -s "$TMP/$tag.oracle.err"
    timeout 10s "$BIN/senschyslo" --в-укр D12 \
      "$TMP/$tag.actual.sens" >"$TMP/$tag.machine.ukr"
    cmp "$TMP/$tag.oracle.out" "$TMP/$tag.machine.ukr"
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 71
cp "$TMP/2-2.elf" "$TMP/occupied.elf"
if timeout 10s "$BIN/sensarithchainelf" --ланцюг-D5 \
  "$TMP/2-2.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err";then
  echo 'наявний ELF було перезаписано' >&2;exit 1;
fi
test ! -s "$TMP/occupied.out" && test -s "$TMP/occupied.err"
cmp "$TMP/occupied.elf" "$TMP/2-2.elf"
cp "$TMP/2-2.sens" "$TMP/projection.lisp"
if timeout 10s "$BIN/sensarithchainelf" --ланцюг-D5 \
  "$TMP/projection.lisp" "$TMP/forbidden.elf" \
  >"$TMP/forbidden.out" 2>"$TMP/forbidden.err";then
  echo 'некоректно прийнято проєкцію .lisp як канонічну' >&2;exit 1;
fi
test ! -s "$TMP/forbidden.out" && test ! -e "$TMP/forbidden.elf"
echo "D5-ARITH-CHAIN-OK physical=71 oracle=71 negative=24 exact-ordered-op=1..16,50,100 no-clobber=yes energy=NOT-MEASURED"
