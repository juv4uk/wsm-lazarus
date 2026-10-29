#!/usr/bin/env bash
# G6.106 — справжні canonical D5(D6(D12),D12) → два machine ALU.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
trap 'echo "D5-D6-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
for tool in git fpc timeout readelf objdump cmp mktemp grep awk dd;do
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
git -C sens-oracle show HEAD:lib/domains/d6.lisp |
  grep -Fq '(001110 (ук додати-1) (укр додати-1)'
git -C sens-oracle show HEAD:lib/domains/d6.lisp |
  grep -Fq '(001111 (ук відняти-1) (укр відняти-1)'
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'не знайдено незалежний pinned SENS REPL' >&2;exit 127;
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/ird5d6compose/units"
BIN="$ROOT/build/m0.2/ird5d6compose/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-ird5d6compose.pas test-ird5d6compose' \
  'src/sensd5d6composeelf.lpr sensd5d6composeelf' \
  'src/senschyslo.lpr senschyslo';do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2;exit 1;
    }
done
if ! timeout 90s "$BIN/test-ird5d6compose" "$TMP" >"$TMP/unit.out" 2>"$TMP/unit.err";then
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1
fi
grep -Fxq 'D5-D6-UNIT-OK positive=16 negative=22' "$TMP/unit.out" || {
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1;
}
COUNT=0
bases=(5 17 127 2030)
rights=(3 -7 11 -2)
for combo in 0 1 2 3;do
  for idx in 0 1 2 3;do
    tag="$combo-$idx"
    EXE="$TMP/$tag.elf"
    test -s "$EXE" && test -s "$TMP/$tag.sens"
    chmod 500 "$EXE"
    readelf -h "$EXE" | grep -Eq 'Type:[[:space:]]+DYN'
    if readelf -l "$EXE" | grep -Eq 'INTERP|DYNAMIC';then
      echo 'ELF має loader або динамічні залежності' >&2;exit 1;
    fi
    timeout 5s "$EXE" >"$TMP/$tag.machine.sens" 2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    cmp "$TMP/$tag.expected.sens" "$TMP/$tag.machine.sens"
    test "$(wc -c <"$TMP/$tag.machine.sens")" -eq 3
    timeout 10s "$BIN/sensd5d6composeelf" --поєднати-D5-D6 \
      "$TMP/$tag.sens" "$TMP/$tag.cli.elf" \
      >"$TMP/$tag.cli.out" 2>"$TMP/$tag.cli.err"
    grep -Fq '0 unfreed memory blocks' "$TMP/$tag.cli.err"
    cmp "$EXE" "$TMP/$tag.cli.elf"
    grep -Fq 'D5-D6-COMPOSE-ELF64' "$TMP/$tag.cli.out"
    dd if="$EXE" of="$TMP/$tag.prefix" bs=1 skip=120 count=15 status=none
    objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.prefix" \
      >"$TMP/$tag.dis"
    grep -Eio '(add|sub)[[:space:]]+eax,' "$TMP/$tag.dis" |
      awk '{print $1}' >"$TMP/$tag.actual.ops"
    : >"$TMP/$tag.expected.ops"
    if ((combo%2==1));then
      inner="(відняти-1 ${bases[idx]})"
      printf 'sub\n' >>"$TMP/$tag.expected.ops"
    else
      inner="(додати-1 ${bases[idx]})"
      printf 'add\n' >>"$TMP/$tag.expected.ops"
    fi
    if ((combo>=2));then
      printf 'sub\n' >>"$TMP/$tag.expected.ops"
      nested="(відняти $inner ${rights[idx]})"
    else
      printf 'add\n' >>"$TMP/$tag.expected.ops"
      nested="(додати $inner ${rights[idx]})"
    fi
    cmp "$TMP/$tag.expected.ops" "$TMP/$tag.actual.ops"
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
test "$COUNT" -eq 16
cp "$TMP/0-0.elf" "$TMP/occupied.elf"
if timeout 10s "$BIN/sensd5d6composeelf" --поєднати-D5-D6 \
  "$TMP/0-0.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err";then
  echo 'наявний ELF помилково перезаписано' >&2;exit 1;
fi
test ! -s "$TMP/occupied.out" && test -s "$TMP/occupied.err"
cmp "$TMP/occupied.elf" "$TMP/0-0.elf"
cp "$TMP/0-0.sens" "$TMP/projection.lisp"
if timeout 10s "$BIN/sensd5d6composeelf" --поєднати-D5-D6 \
  "$TMP/projection.lisp" "$TMP/forbidden.elf" \
  >"$TMP/forbidden.out" 2>"$TMP/forbidden.err";then
  echo 'помилкове прийняття проєкції .lisp як canonical' >&2;exit 1;
fi
test ! -s "$TMP/forbidden.out" && test ! -e "$TMP/forbidden.elf"
echo "D5-D6-COMPOSE-OK physical=16 oracle=16 negative=22 ordered-ALU=2 no-clobber=yes energy=NOT-MEASURED"
