#!/usr/bin/env bash
# G6.85 — два D6 предикати, machine TEST+SETcc, exact D12→D1 T5M.
# Результат не доведений лише виходом FPC: pinned SENS oracle обов'язковий в CI.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
trap 'echo "Д6-ПАРНІСТЬ-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
for cmd in git timeout fpc readelf objdump cmp mktemp; do
  command -v "$cmd" >/dev/null || { echo "Д6-ПАРНІСТЬ-БЛОК: немає $cmd" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д6-ПАРНІСТЬ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
./scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# sparse checkout має D6, але machine ISA може лишатися тільки git object.
grep -Fq '(010000 (ук парне?) (укр парне?)' external/sens/lib/domains/d6.lisp
grep -Fq '(010001 (ук непарне?) (укр непарне?)' external/sens/lib/domains/d6.lisp
git -C external/sens show HEAD:lib/machine/isa/x86-base.lisp >"$TMP/x86-isa.lisp"
grep -Fq '(instruction TEST' "$TMP/x86-isa.lisp"
grep -Fq '(form test-r64-imm32' "$TMP/x86-isa.lisp"
grep -Fq '(first-domain . D12)' external/sens/contracts/language-contract-12.lisp
mkdir -p "$TMP/units" "$TMP/bin"
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
 -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
 -osensd6parnistelf "$ROOT/src/sensd6parnistelf.lpr" >"$TMP/fpc.log" 2>&1 || {
   cat "$TMP/fpc.log" >&2; exit 1;
 }
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
 -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
 -otest-d6-parnist-elf "$ROOT/scripts/test-d6-parnist-elf.pas" >"$TMP/fpc.log" 2>&1 || {
   cat "$TMP/fpc.log" >&2; exit 1;
 }
timeout 20s "$TMP/bin/test-d6-parnist-elf" "$TMP"
CLI="$TMP/bin/sensd6parnistelf"
test -x "$CLI"
COUNT=0
for row in 'd6-01:-2048:1:0' 'd6-02:-2047:0:1' 'd6-03:-1024:1:0' \
           'd6-04:-3:0:1' 'd6-05:-2:1:0' 'd6-06:-1:0:1' \
           'd6-07:0:1:0' 'd6-08:1:0:1' 'd6-09:2046:1:0' 'd6-10:2047:0:1'; do
  IFS=: read -r tag number even odd <<<"$row"
  for mode in even odd; do
    if [[ $mode == even ]]; then flag='--парне-D12'; wanted=$even
    else flag='--непарне-D12'; wanted=$odd; fi
    timeout 10s "$CLI" "$flag" "$TMP/$tag.sens" "$TMP/$tag.$mode.elf" \
      >"$TMP/build.stdout" 2>"$TMP/build.stderr" || {
        cat "$TMP/build.stderr" >&2; exit 1;
      }
    test ! -s "$TMP/build.stderr"
    test -x "$TMP/$tag.$mode.elf"
    readelf -h "$TMP/$tag.$mode.elf" >"$TMP/header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
    timeout 5s "$TMP/$tag.$mode.elf" >"$TMP/$tag.$mode.actual.sens"
    cmp "$TMP/$tag.$mode.sens" "$TMP/$tag.$mode.actual.sens"
    test "$(wc -c <"$TMP/$tag.$mode.actual.sens")" -eq 1
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 20
# У реально створених ELF немає precomputed answer: pinned TEST REX.W F7 /0, bit0 та різні SETcc.
for mode in even odd; do
  tail -c +121 "$TMP/d6-08.$mode.elf" >"$TMP/$mode.machine"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$mode.machine" >"$TMP/$mode.asm"
  grep -Eiq 'test[[:space:]]+rax,0x1' "$TMP/$mode.asm"
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$mode.asm"
done
grep -Eiq 'sete[[:space:]]+al' "$TMP/even.asm"
grep -Eiq 'setne[[:space:]]+al' "$TMP/odd.asm"
# Негативи: exact domain, payload, text projection і atomic no-clobber.
REJECTED=0
reject() {
  local name=$1; shift
  local dest="$TMP/rejected-$name.elf" rc=0
  timeout 10s "$CLI" "$@" "$dest" >"$TMP/reject.stdout" 2>"$TMP/reject.stderr" || rc=$?
  test "$rc" -eq 2
  test ! -e "$dest"
  test ! -s "$TMP/reject.stdout"
  test -s "$TMP/reject.stderr"
  REJECTED=$((REJECTED+1))
}
cp "$TMP/d6-08.sens" "$TMP/projection.lisp"
for flag in '--парне-D12' '--непарне-D12'; do
  reject "width-d24-$REJECTED" "$flag" "$TMP/bad24.sens"
  reject "width-d1-$REJECTED" "$flag" "$TMP/bad1.sens"
  reject "text-d7-$REJECTED" "$flag" "$TMP/bad7.sens"
  reject "corrupt-$REJECTED" "$flag" "$TMP/corrupt.sens"
  reject "empty-$REJECTED" "$flag" "$TMP/empty.sens"
  reject "projection-$REJECTED" "$flag" "$TMP/projection.lisp"
  reject "missing-$REJECTED" "$flag" "$TMP/absent.sens"
done
reject unknown-mode --unknown "$TMP/d6-08.sens"
test "$REJECTED" -eq 15
cp "$TMP/d6-08.even.elf" "$TMP/existing.elf"
rc=0
timeout 10s "$CLI" --парне-D12 "$TMP/d6-08.sens" "$TMP/existing.elf" \
 >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/existing.elf" "$TMP/d6-08.even.elf"

# Шар звірки з REPL: ТАК / НІ (контракт D1:1=ТАК, D1:0=НІ).
# Машина дає канонічний байт 1/0; очікування для oracle — ТАК/НІ.
normalize_oracle_tak_ni() {
  awk '
    {
      sub(/\r$/, ""); sub(/[ \t]+$/, "");
      line=$0;
      sub(/^sens\[[^]]+\]> /, "", line);
      if (line ~ /(ПОМИЛКА|помилка|ERROR|Error|error)/) bad=1;
      if (line ~ /^\([ \t]*т[ \t]+а[ \t]+к[ \t]*\)$/) line="ТАК";
      if (line ~ /^\([ \t]*н[ \t]+і[ \t]*\)$/) line="НІ";
      if (line=="1" || line=="так" || line=="ТАК") line="ТАК";
      if (line=="0" || line=="ні" || line=="НІ") line="НІ";
      if (line=="ТАК" || line=="НІ") { print line; found=1 }
    }
    END { if (bad) exit 48; if (!found) exit 49 }
  ' "$1"
}

# Порівнюємо кожен справжній machine D1 з незалежним SENS REPL на шарі ТАК/НІ.
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  ORACLE=0
  NOTVER=0
  for row in 'd6-01:-2048:1:0' 'd6-02:-2047:0:1' 'd6-03:-1024:1:0' \
             'd6-04:-3:0:1' 'd6-05:-2:1:0' 'd6-06:-1:0:1' \
             'd6-07:0:1:0' 'd6-08:1:0:1' 'd6-09:2046:1:0' 'd6-10:2047:0:1'; do
    IFS=: read -r tag number even odd <<<"$row"
    for mode in even odd; do
      if [[ $mode == even ]]; then name='парне?'; wanted_bit=$even
      else name='непарне?'; wanted_bit=$odd; fi
      if [[ "$wanted_bit" == "1" ]]; then wanted='ТАК'; else wanted='НІ'; fi
      printf '(%s %s)\n' "$name" "$number" >"$TMP/$tag.$mode.lisp"
      printf '%s\n' "$wanted" >"$TMP/$tag.$mode.wanted"

      rc=0
      timeout 40s "$SENS_ORACLE_BIN" --surface=укр <"$TMP/$tag.$mode.lisp" \
        >"$TMP/$tag.$mode.oracle" 2>"$TMP/$tag.$mode.oracle.err" || rc=$?

      if [[ $rc -ne 0 || -s "$TMP/$tag.$mode.oracle.err" ]]; then
        echo "Д6-ПАРНІСТЬ-ORACLE-ВІДМОВА $tag/$mode numeric=$number code=$rc" >&2
        head -n 3 "$TMP/$tag.$mode.oracle.err" >&2 || true
        NOTVER=$((NOTVER+1))
        continue
      fi
      if ! normalize_oracle_tak_ni "$TMP/$tag.$mode.oracle" >"$TMP/$tag.$mode.oracle.word"; then
        echo "Д6-ПАРНІСТЬ-ORACLE-НЕ-ТАК-НІ $tag/$mode numeric=$number" >&2
        head -c 120 "$TMP/$tag.$mode.oracle" >&2 || true
        NOTVER=$((NOTVER+1))
        continue
      fi
      if ! cmp -s "$TMP/$tag.$mode.wanted" "$TMP/$tag.$mode.oracle.word"; then
        echo "Д6-ПАРНІСТЬ-ORACLE-РОЗБІЖНІСТЬ $tag/$mode numeric=$number" >&2
        echo "  очікували: $(cat "$TMP/$tag.$mode.wanted")" >&2
        echo "  оракул:    $(cat "$TMP/$tag.$mode.oracle.word")" >&2
        exit 1
      fi
      ORACLE=$((ORACLE+1))
    done
  done
  if [[ "$ORACLE" -eq 20 ]]; then
    echo "Д6-ПАРНІСТЬ-ОРАКУЛ-ГАРАЗД фізичних=$COUNT незалежних=$ORACLE шар=ТАК/НІ pin=$PIN"
  elif [[ $((ORACLE+NOTVER)) -eq 20 ]]; then
    echo "Д6-ПАРНІСТЬ-ОРАКУЛ-NOT-VERIFIED підтверджено=$ORACLE відмова=$NOTVER з=20 pin=$PIN"
    echo "  machine ELF PASS; upstream не підтвердив усі форми — не заявляємо повний паритет" >&2
  else
    echo "Д6-ПАРНІСТЬ-НЕМАЄ-UPSTREAM-ПАРИТЕТУ підтверджено=$ORACLE відмова=$NOTVER з=20" >&2
    exit 1
  fi
fi
echo "Д6-ПАРНІСТЬ-ELF-ГАРАЗД FPC=checked TEST/SETE/SETNE=так D1-T5M=$COUNT негативи=$REJECTED енергія=НЕ-ВИМІРЯНА"
