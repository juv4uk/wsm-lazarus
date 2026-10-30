#!/usr/bin/env bash
# G6.156: фізичні mixed D5 → СПІЛЬНИЙ verified WideIR → ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc!=0));then
    echo "ЗМІШАНИЙ-WIDEIR-ПРОВАЛ: рядок=$1 код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err "$TMP"/negative.stderr;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'finish "$LINENO"' EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for tool in fpc git timeout cmp readelf objdump python3 grep mktemp stat chmod tail;do
  command -v "$tool" >/dev/null || { echo "Немає $tool" >&2;exit 127; }
done
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01010 (ук додати) (укр додати)'
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01011 (ук відняти) (укр відняти)'
ORACLE=$(printenv SENS_ORACLE_BIN || true)
REQUIRE=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ $REQUIRE == 1 && -z $ORACLE ]];then
  echo 'ЗМІШАНИЙ-WIDEIR-БЛОК: потрібен незалежний SENS REPL' >&2;exit 127
fi
if [[ -n $ORACLE ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-irarithderevo.pas test-irarithderevo' \
  'scripts/test-irwidefront-mixed-d5.pas test-irwidefront-mixed-d5' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senschyslo.lpr senschyslo';do
  read -r src name <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name-build.log" 2>&1 || {
      cat "$TMP/$name-build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 180s "$TMP/bin/test-irarithderevo" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Eq 'positive=32[[:space:]]+negative=17' "$TMP/generator.log"
timeout 30s "$TMP/bin/test-irwidefront-mixed-d5" "$TMP/physical" \
  >"$TMP/negative-generator.log" 2>"$TMP/negative-generator.err"
grep -Fq 'cases=7 projection=1' "$TMP/negative-generator.log"
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1";then
    grep -Fq '0 unfreed memory blocks' "$1"
  fi
}
check_heap "$TMP/generator.err"
check_heap "$TMP/negative-generator.err"

POS=0;ORACLE_COUNT=0
# Збалансовані та нерегулярні дерева: по 6 розмірів, 3..31 операція.
for shape in 2 3;do
  for depth in 3 5 8 12 20 31;do
    label="$shape-$depth"
    src="$TMP/physical/$label.sens"
    out="$TMP/$label.shared.elf"
    timeout 30s "$TMP/bin/senswidefrontelf" \
      --скомпілювати-фізичну-форму "$src" "$out" \
      >"$TMP/$label-front.log" 2>"$TMP/$label-front.err"
    grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' \
      "$TMP/$label-front.log"
    check_heap "$TMP/$label-front.err"
    test -x "$out"
    test "$(stat -c '%a' "$out")" = 700
    cmp "$out" "$TMP/physical/$label.elf"
    timeout 5s readelf -h "$out" >"$TMP/$label-header.log"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label-header.log"
    ! readelf -l "$out" | grep -Eq 'INTERP|DYNAMIC'
    tail -c +121 "$out" >"$TMP/$label-code"
    timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/$label-code" >"$TMP/$label-dis.log"
    # Після G6.172 лише два вкладені операнди потребують PUSH/POP.
    # Старий grep вимагав стек для КОЖНОГО дерева, що суперечило
    # машинній оптимізації атом+піддерево. Нижче перевіряємо саме
    # інструкції до канонічного T5M writer, не ELF header/data.
    # Мінімальна ISA: MOV EAX,imm32; ADD/SUB EAX,imm32;
    # NEG EAX+ADD; PUSH/POP; ADD EAX,ECX; SUB ECX,EAX/MOV EAX,ECX.
    python3 - "$out" "$depth" "$shape" <<'PY'
from pathlib import Path
import sys

image=Path(sys.argv[1]).read_bytes()
operations=int(sys.argv[2])
shape=int(sys.argv[3])
pc=120
mov=push=pop=add=sub=immediate=neg=0
stack=0
marker=bytes.fromhex('25ff0f0000')
while True:
    assert pc+5<=len(image),('машинний writer не знайдено',pc)
    if image[pc:pc+5]==marker:
        break
    if image[pc]==0xB8:
        assert pc+5<=len(image)
        mov+=1;pc+=5
    elif image[pc]==0x50:
        push+=1;stack+=1;pc+=1
    elif image[pc]==0x59:
        pop+=1;stack-=1;pc+=1
        assert stack>=0,('POP без PUSH',pc)
    elif image[pc:pc+3]==bytes.fromhex('f7d805'):
        assert pc+7<=len(image),'обірваний NEG+ADD imm32'
        value=int.from_bytes(image[pc+3:pc+7],'little',signed=True)
        assert -2048<=value<=2047,('ліва D12 константа не signed',value)
        neg+=1;sub+=1;immediate+=1;pc+=7
    elif image[pc] in (0x05,0x2D):
        assert pc+5<=len(image),'обірваний ADD/SUB imm32'
        value=int.from_bytes(image[pc+1:pc+5],'little',signed=True)
        assert -2048<=value<=2047,('D12 immediate поза межею',value)
        if image[pc]==0x05:
            add+=1
        else:
            sub+=1
        immediate+=1;pc+=5
    elif image[pc:pc+2]==bytes.fromhex('01c8'):
        add+=1;pc+=2
    elif image[pc:pc+4]==bytes.fromhex('29c189c8'):
        sub+=1;pc+=4
    else:
        raise AssertionError(('невідома машинна команда',pc,image[pc:pc+5].hex()))
    assert pc<4096,'machine island вийшов за квоту'
assert stack==0,('непарний PUSH/POP',push,pop,stack)
assert add+sub==operations,('втрачено D5 вузол',add,sub,operations)
assert mov==operations+1-immediate,(mov,operations,immediate)
assert push==pop==operations-immediate,(push,pop,operations,immediate)
if shape==2:
    # Збалансоване дерево з двома вкладеними дітьми має потребувати
    # принаймні один справжній машинний стековий кадр.
    assert push>0 and pop>0,('балансне дерево втратило стек',push,pop)
else:
    # Нерегулярні дерева з одним вкладеним піддеревом більше НЕ
    # зобов'язані мати стек; замість цього вимагаємо реальний imm32.
    assert immediate>=1,('оптимізований шлях відсутній',immediate)
PY
    timeout 5s "$out" >"$TMP/$label-actual.sens" \
      2>"$TMP/$label-machine.err"
    test ! -s "$TMP/$label-machine.err"
    cmp "$TMP/physical/$label.expected.sens" "$TMP/$label-actual.sens"
    timeout 5s "$TMP/bin/senschyslo" --в-укр D12 \
      "$TMP/$label-actual.sens" >"$TMP/$label-ukr" 2>"$TMP/$label-ukr.err"
    test ! -s "$TMP/$label-ukr.err"
    if [[ -n "$ORACLE" ]];then
      timeout 45s "$ORACLE" "$TMP/physical/$label.oracle.lisp" \
        >"$TMP/$label-oracle" 2>"$TMP/$label-oracle.err"
      test ! -s "$TMP/$label-oracle.err"
      cmp "$TMP/$label-ukr" "$TMP/$label-oracle"
      ORACLE_COUNT=$((ORACLE_COUNT+1))
    fi
    POS=$((POS+1))
  done
done
test "$POS" -eq 12
if [[ -n "$ORACLE" ]];then test "$ORACLE_COUNT" -eq 12;fi

NEG=0
reject() {
  local arg="$1" output="$TMP/reject-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" \
    --скомпілювати-фізичну-форму "$arg" "$output" \
    >"$TMP/negative.stdout" 2>"$TMP/negative.stderr" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/negative.stdout"
  test ! -e "$output" && test ! -L "$output"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.stderr"
  check_heap "$TMP/negative.stderr"
  NEG=$((NEG+1))
}
for bad in bad-root-mul bad-inner-d6 bad-leaf-d24 bad-d2-close \
           bad-two-roots bad-t5m bad-empty;do
  reject "$TMP/physical/$bad.sens"
done
reject "$TMP/physical/not-physical.lisp"
test "$NEG" -eq 8
cp "$TMP/2-8.shared.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" \
  --скомпілювати-фізичну-форму "$TMP/physical/2-8.sens" \
  "$TMP/occupied.elf" >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/2-8.shared.elf" "$TMP/occupied.elf"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" \
  --скомпілювати-фізичну-форму "$TMP/physical/3-8.sens" \
  "$TMP/dangling.elf" >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/missing.elf" && test ! -s "$TMP/no-clobber.out"
timeout 25s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
  "$TMP/physical/2-8.sens" "$TMP/recovered.elf" >/dev/null
cmp "$TMP/recovered.elf" "$TMP/2-8.shared.elf"
echo "ЗМІШАНИЙ-WIDEIR-D5-ГАРАЗД physical=$POS elf=$POS native=$POS exact=$POS oracle=$ORACLE_COUNT negative=$NEG no-clobber=2 recovery=1 energy=NOT-MEASURED"
timeout 480s bash scripts/test-irwidefront.sh
