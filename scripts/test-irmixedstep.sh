#!/usr/bin/env bash
# G6.101 — binary-first D6 ADD1/SUB1, один реальний ELF із N ADD/SUB.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
trap 'echo "D6-ЗМІШАНІ-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
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
UNITS="$ROOT/build/m0.2/irmixedstep/units"
BIN="$ROOT/build/m0.2/irmixedstep/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-irmixedstep.pas test-irmixedstep' \
  'src/sensmixedstepelf.lpr sensmixedstepelf' \
  'src/senschyslo.lpr senschyslo';do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2;exit 1;
    }
done
if ! timeout 90s "$BIN/test-irmixedstep" "$TMP" >"$TMP/unit.out" 2>"$TMP/unit.err";then
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1
fi
grep -Fxq 'D6-MIXED-UNIT-OK positive=64 negative=17' "$TMP/unit.out" || {
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1;
}
COUNT=0
bases=(5 17 512 2040)
for depth in {1..16};do
  for pattern in 0 1 2 3;do
    tag="$depth-$pattern"
    EXE="$TMP/$tag.elf"
    chmod 500 "$EXE"
    readelf -h "$EXE" | grep -Eq 'Type:[[:space:]]+DYN'
    if readelf -l "$EXE" | grep -Eq 'INTERP|DYNAMIC';then
      echo 'ELF не повинен мати loader' >&2;exit 1;
    fi
    timeout 5s "$EXE" >"$TMP/$tag.machine.sens" 2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    cmp "$TMP/$tag.expected.sens" "$TMP/$tag.machine.sens"
    test "$(wc -c <"$TMP/$tag.machine.sens")" -eq 3
    timeout 10s "$BIN/sensmixedstepelf" --змішані-D6 \
      "$TMP/$tag.sens" "$TMP/$tag.cli.elf" \
      >"$TMP/$tag.cli.out" 2>"$TMP/$tag.cli.err"
    grep -Fq '0 unfreed memory blocks' "$TMP/$tag.cli.err"
    cmp "$EXE" "$TMP/$tag.cli.elf"
    grep -Fq 'D6-MIXED-ELF64' "$TMP/$tag.cli.out"
    dd if="$EXE" of="$TMP/$tag.prefix" bs=1 skip=120 \
      count=$((5+5*depth)) status=none
    objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.prefix" \
      >"$TMP/$tag.dis"
    grep -Eio '(add|sub)[[:space:]]+eax,' "$TMP/$tag.dis" |
      awk '{print $1}' >"$TMP/$tag.actual.ops"
    : >"$TMP/$tag.expected.ops"
    if (( depth>5 && pattern==3 ));then nested=2000
    else nested="${bases[pattern]}"
    fi
    for ((z=0;z<depth;z++));do
      if ((pattern==2 || (pattern==0 && z%2==0) || (pattern==1 && z%2==1)));then
        printf 'sub\n' >>"$TMP/$tag.expected.ops"
        nested="(відняти-1 $nested)"
      else
        printf 'add\n' >>"$TMP/$tag.expected.ops"
        nested="(додати-1 $nested)"
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
      "$TMP/$tag.machine.sens" >"$TMP/$tag.machine.ukr"
    cmp "$TMP/$tag.oracle.out" "$TMP/$tag.machine.ukr"
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 64
cp "$TMP/2-1.elf" "$TMP/occupied.elf"
if timeout 10s "$BIN/sensmixedstepelf" --змішані-D6 \
  "$TMP/2-1.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err";then
  echo 'наявний ELF перезаписано' >&2;exit 1;
fi
test ! -s "$TMP/occupied.out" && test -s "$TMP/occupied.err"
cmp "$TMP/occupied.elf" "$TMP/2-1.elf"
cp "$TMP/2-1.sens" "$TMP/projection.lisp"
if timeout 10s "$BIN/sensmixedstepelf" --змішані-D6 \
  "$TMP/projection.lisp" "$TMP/forbidden.elf" \
  >"$TMP/forbidden.out" 2>"$TMP/forbidden.err";then
  echo 'помилкове прийняття текстової проєкції' >&2;exit 1;
fi
test ! -s "$TMP/forbidden.out" && test ! -e "$TMP/forbidden.elf"
echo "D6-MIXED-OK physical=64 oracle=64 negative=17 ordered-machine=1..16 no-clobber=yes energy=NOT-MEASURED"
