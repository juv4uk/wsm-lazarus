#!/usr/bin/env bash
# G6.90 — один ELF із двома реальними ADD над nested D6 формою.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
trap 'echo "D6-ДВІЧІ-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
for tool in git fpc timeout readelf objdump cmp mktemp grep; do
  command -v "$tool" >/dev/null || { echo "D6-ДВІЧІ-БЛОК: потрібен $tool" >&2;exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D6-ДВІЧІ-БЛОК: потрібен Linux x86-64' >&2;exit 127;
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
  echo 'D6-ДВІЧІ-БЛОК: немає незалежного SENS REPL' >&2;exit 127;
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/ird6doubleadd/units"
BIN="$ROOT/build/m0.2/ird6doubleadd/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for row in   'scripts/test-ird6doubleadd.pas test-ird6doubleadd'   'src/sensd6doubleaddelf.lpr sensd6doubleaddelf'   'src/senschyslo.lpr senschyslo';do
  read -r source executable <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh     -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "-o$executable"     "$ROOT/$source" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2;exit 1;
    }
done
if ! timeout 90s "$BIN/test-ird6doubleadd" "$TMP" >"$TMP/unit.out" 2>"$TMP/unit.err";then
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1
fi
grep -Fxq 'D6-DOUBLE-UNIT-OK positive=12 negative=12' "$TMP/unit.out" || {
  cat "$TMP/unit.out" "$TMP/unit.err" >&2;exit 1;
}
PASS=0
for row in   '0:-2048:-2046' '1:-2000:-1998' '2:-5:-3'   '3:-2:0' '4:-1:1' '5:0:2'   '6:1:3' '7:2:4' '8:127:129'   '9:512:514' '10:1024:1026' '11:2045:2047';do
  IFS=: read -r tag number expected <<< "$row"
  SOURCE="$TMP/$tag.sens"; EXE="$TMP/$tag.elf"
  test -s "$SOURCE" && test -s "$EXE"
  chmod 500 "$EXE"
  readelf -h "$EXE" | grep -Eq 'Type:[[:space:]]+DYN'
  if readelf -l "$EXE" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'D6-ДВІЧІ-БЛОК: ELF має динамічні залежності' >&2;exit 1;
  fi
  timeout 5s "$EXE" >"$TMP/$tag.machine.sens" 2>"$TMP/$tag.machine.err"
  test ! -s "$TMP/$tag.machine.err"
  cmp "$TMP/$tag.expected.sens" "$TMP/$tag.machine.sens"
  test "$(wc -c <"$TMP/$tag.machine.sens")" -eq 3
  timeout 10s "$BIN/sensd6doubleaddelf" --двічі-додати-1     "$SOURCE" "$TMP/$tag.cli.elf" >"$TMP/$tag.cli.out" 2>"$TMP/$tag.cli.err"
  test ! -s "$TMP/$tag.cli.err"
  cmp "$EXE" "$TMP/$tag.cli.elf"
  grep -Fq 'machine-ADD=2' "$TMP/$tag.cli.out"
  # Лише 15 байтів executable prefix: MOV + ADD + ADD, без таблиць.
  dd if="$EXE" of="$TMP/$tag.prefix" bs=1 skip=120 count=15 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.prefix"     >"$TMP/$tag.dis"
  test "$(grep -Eic 'add[[:space:]]+eax,' "$TMP/$tag.dis")" -eq 2
  printf '(додати-1 (додати-1 %s))\n' "$number"     >"$TMP/$tag.oracle.lisp"
  timeout 60s "$ORACLE" "$TMP/$tag.oracle.lisp"     >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err" || {
      cat "$TMP/$tag.oracle.err" >&2;exit 1;
    }
  test ! -s "$TMP/$tag.oracle.err"
  printf '%s\n' "$expected" >"$TMP/$tag.expected.ukr"
  cmp "$TMP/$tag.oracle.out" "$TMP/$tag.expected.ukr"
  timeout 10s "$BIN/senschyslo" --в-укр D12     "$TMP/$tag.machine.sens" >"$TMP/$tag.machine.ukr"
  cmp "$TMP/$tag.oracle.out" "$TMP/$tag.machine.ukr"
  PASS=$((PASS+1))
done
test "$PASS" -eq 12
# Справжній no-clobber: наявний ELF не змінити навіть правильним входом.
cp "$TMP/6.elf" "$TMP/occupied.elf"
if timeout 10s "$BIN/sensd6doubleaddelf" --двічі-додати-1   "$TMP/6.sens" "$TMP/occupied.elf"   >"$TMP/occupied.out" 2>"$TMP/occupied.err";then
  echo 'D6-ДВІЧІ-ПРОВАЛ: existing ELF перезаписаний' >&2;exit 1;
fi
test ! -s "$TMP/occupied.out"
test -s "$TMP/occupied.err"
cmp "$TMP/occupied.elf" "$TMP/6.elf"
cp "$TMP/6.sens" "$TMP/projection.lisp"
if "$BIN/sensd6doubleaddelf" --двічі-додати-1     "$TMP/projection.lisp" "$TMP/forbidden.elf"     >"$TMP/projection.out" 2>"$TMP/projection.err";then
  echo 'D6-ДВІЧІ-ПРОВАЛ: прийнято .lisp' >&2;exit 1;
fi
test ! -e "$TMP/forbidden.elf" && test ! -s "$TMP/projection.out"
echo "D6-ПОДВІЙНЕ-ДОДАВАННЯ-ГАРАЗД physical-elf=$PASS oracle=$PASS negatives=12 no-clobber=yes nested-ir=yes energy=NOT-MEASURED"
