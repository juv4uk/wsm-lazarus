#!/usr/bin/env bash
# G6.62: наявні exact IR emitters, перевірені тим самим фізичним T5M.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for cmd in git fpc readelf stat timeout cmp; do
  command -v "$cmd" >/dev/null || { echo "АВТО-БЛОК: відсутній $cmd" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
test -x "$ROOT/sens-oracle/target/debug/sens"
timeout 240s bash scripts/test-sensmashyna.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
 -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
 -osensmashyna "$ROOT/src/sensmashyna.lpr"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
 -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
 -otest-senselfvykon "$ROOT/scripts/test-senselfvykon.pas"
timeout 15s "$TMP/bin/test-senselfvykon" "$TMP/свідки"
CLI="$TMP/bin/sensmashyna"
SENS="$ROOT/sens-oracle/target/debug/sens"
POS=0 ORACLE=0
for row in \
 'p01:цитата:DYN:' 'p02:цитата:DYN:1' \
 'p03:атом:EXEC:0' 'p04:атом:EXEC:1' \
 'p05:тотожність:DYN:0' 'p06:тотожність:DYN:1' \
 'p07:селектор:DYN:1' 'p08:селектор:DYN:0' \
 'p09:умова:EXEC:1' 'p10:умова:EXEC:()'; do
  IFS=: read -r label mode kind expected <<< "$row"
  source="$TMP/свідки/$label.sens"
  timeout 20s "$CLI" "--$mode" "$ROOT/external/sens" "$source" \
    "$TMP/$label.explicit.elf" >"$TMP/$label.explicit.out" 2>"$TMP/$label.explicit.err"
  timeout 20s "$CLI" --автоматично "$ROOT/external/sens" "$source" \
    "$TMP/$label.auto.elf" >"$TMP/$label.auto.out" 2>"$TMP/$label.auto.err"
  cmp "$TMP/$label.explicit.elf" "$TMP/$label.auto.elf"
  test -x "$TMP/$label.auto.elf"
  test "$(stat -c %a "$TMP/$label.auto.elf")" = 700
  grep -F ELF64-x86-64 "$TMP/$label.auto.out" >/dev/null
  if [[ -s "$TMP/$label.auto.err" ]]; then
    grep -F '0 unfreed memory blocks' "$TMP/$label.auto.err" >/dev/null
    ! grep -Fq 'НАТИВНИЙ-ELF-ПОМИЛКА:' "$TMP/$label.auto.err"
  fi
  readelf -h "$TMP/$label.auto.elf" >"$TMP/$label.header"
  grep -F ELF64 "$TMP/$label.header" >/dev/null
  grep -Eq "Type:.*$kind" "$TMP/$label.header"
  timeout 5s "$TMP/$label.auto.elf" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$TMP/свідки/$label.expected.sens"
  POS=$((POS+1))
  # D7 SYN — точні дані без надуманої друкованої укр проєкції.
  if [[ -n "$expected" ]]; then
    timeout 45s "$SENS" "$source" >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
    ORACLE=$((ORACLE+1))
  fi
done
test "$POS" -eq 10 && test "$ORACLE" -eq 9

NEG=0
reject() {
  local label="$1";shift
  local output="$TMP/$label.elf" status=0
  timeout 15s "$CLI" --автоматично "$@" "$output" \
    >"$TMP/$label.stdout" 2>"$TMP/$label.stderr" || status=$?
  if [[ "$status" -ne 2 ]]; then
    echo "АВТО-ПОМИЛКА: негатив=$label код=$status" >&2
    cat "$TMP/$label.stderr" >&2
    exit 1
  fi
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/$label.stdout"
  grep -F ELF- "$TMP/$label.stderr" >/dev/null
  NEG=$((NEG+1))
}
reject голий-д1 "$ROOT/external/sens" "$TMP/свідки/bare-d1.sens"
reject хибний-т5м "$ROOT/external/sens" "$TMP/свідки/bad-t5m.sens"
reject незакритий "$ROOT/external/sens" "$TMP/свідки/truncated.sens"
reject числовий-атом "$ROOT/external/sens" "$TMP/свідки/d12-atom.sens"
reject числова-умова "$ROOT/external/sens" "$TMP/свідки/d12-cond.sens"
reject порожній "$ROOT/external/sens" "$TMP/свідки/empty.sens"
reject перевищений "$ROOT/external/sens" "$TMP/свідки/huge.sens"
cat "$TMP/свідки/p02.sens" "$TMP/свідки/p06.sens" >"$TMP/два-корені.sens"
reject два-корені "$ROOT/external/sens" "$TMP/два-корені.sens"
cp "$TMP/свідки/p02.sens" "$TMP/підміна.lisp"
reject текстова-підміна "$ROOT/external/sens" "$TMP/підміна.lisp"
cp "$TMP/свідки/p09.sens" "$TMP/пізня-підміна.sens"
printf '\363' >>"$TMP/пізня-підміна.sens"
reject пізній-байт "$ROOT/external/sens" "$TMP/пізня-підміна.sens"
reject немає-кореня "$TMP/неіснуючий" "$TMP/свідки/p02.sens"
cp "$TMP/p02.auto.elf" "$TMP/зайнятий.elf"
status=0
timeout 15s "$CLI" --автоматично "$ROOT/external/sens" \
 "$TMP/свідки/p02.sens" "$TMP/зайнятий.elf" \
 >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/зайнятий.elf" "$TMP/p02.auto.elf"
NEG=$((NEG+1))
ln -s "$TMP/відсутній.elf" "$TMP/посилання.elf"
status=0
timeout 15s "$CLI" --автоматично "$ROOT/external/sens" \
 "$TMP/свідки/p02.sens" "$TMP/посилання.elf" \
 >"$TMP/symlink.out" 2>"$TMP/symlink.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/symlink.out"
test -L "$TMP/посилання.elf" && test ! -e "$TMP/відсутній.elf"
NEG=$((NEG+1))
test "$NEG" -eq 13
echo "МАШИНА-АВТО-ГАРАЗД exact-ELF=$POS незалежний-SENS=$ORACLE негативів=$NEG без-перезапису=2 D3=точно D7=дані D12+=окремо"
# Типи: T5M input/ELF — сирі bytes; $TMP — owned temp files; trap
# видаляє їх. Питання: чому весь ELF має збігатися? Чому D7 SYN
# не друкуємо як мовний закон? Де перевіряється арність? Хто
# звільняє тимчасові файли й чому ніякий ELF не з'являється на відмові?
