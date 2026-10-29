#!/usr/bin/env bash
# G6.97: реальний checked FPC + 24 ELF64 PIE + D1 T5M + pinned oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д6-МЕЖІ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for tool in fpc timeout cmp python3 readelf objdump; do
  command -v "$tool" >/dev/null || { echo "Д6-МЕЖІ-БЛОК: немає $tool" >&2; exit 127; }
done
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(110100 (ук не-більше?) (укр не-більше?)' external/sens/lib/domains/d6.lisp
grep -Fq '(110110 (ук не-менше?) (укр не-менше?)' external/sens/lib/domains/d6.lisp
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then for f in "$TMP"/*.err "$TMP"/*.log; do if [[ -s "$f" ]]; then echo "-- $f" >&2; tail -25 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-test" "$TMP/witnesses"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
 -FU"$TMP/units-cli" -FE"$TMP/bin" -osensd6mezhyelf \
 "$ROOT/src/sensd6mezhyelf.lpr" >"$TMP/cli.log" 2>&1 || { cat "$TMP/cli.log" >&2; exit 1; }
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
 -FU"$TMP/units-test" -FE"$TMP/bin" -otest-elfd12bilsh \
 "$ROOT/scripts/test-elfd12bilsh.pas" >"$TMP/test.log" 2>&1 || { cat "$TMP/test.log" >&2; exit 1; }
test -x "$TMP/bin/sensd6mezhyelf" && test -x "$TMP/bin/test-elfd12bilsh"
timeout 30s "$TMP/bin/test-elfd12bilsh" "$TMP/witnesses" >"$TMP/matrix.tsv" 2>"$TMP/fixture.err"
test "$(wc -l <"$TMP/matrix.tsv")" -eq 12
YES="$TMP/witnesses/03-expected.sens"
NO="$TMP/witnesses/01-expected.sens"
test -s "$YES" && test -s "$NO"
COUNT=0; ORACLE=0
while IFS=$'\t' read -r label left right previous; do
  for mode in 110100 110110; do
    if [[ "$mode" == 110100 ]]; then
      if (( left<=right )); then answer=ТАК; expected="$YES"; else answer=НІ; expected="$NO"; fi
      opname='не-більше?'; opcode='0f9ec0'
    else
      if (( left>=right )); then answer=ТАК; expected="$YES"; else answer=НІ; expected="$NO"; fi
      opname='не-менше?'; opcode='0f9dc0'
    fi
    ELF="$TMP/$label-$mode.elf"
    timeout 12s "$TMP/bin/sensd6mezhyelf" "--D6-$mode" \
      "$TMP/witnesses/$label-l.sens" "$TMP/witnesses/$label-r.sens" "$ELF" \
      >"$TMP/status.log" 2>"$TMP/run.err"
    test ! -s "$TMP/run.err"
    grep -Fq 'machine=CMP/SETcc stdout=T5M-D1' "$TMP/status.log"
    test -x "$ELF"
    readelf -h "$ELF" | grep -Eq 'Type:.*DYN'
    timeout 5s "$ELF" >"$TMP/answer.sens"
    cmp "$expected" "$TMP/answer.sens"
    python3 - "$ELF" "$opcode" <<'PY'
from pathlib import Path
import sys
data=Path(sys.argv[1]).read_bytes()
assert data[:4] == b'\x7fELF'
assert bytes.fromhex(sys.argv[2]) in data[120:160]
assert data.count(b'\x0f\x05') == 2
PY
    timeout 12s "$TMP/bin/sensd6mezhyelf" "--D6-$mode" \
      "$TMP/witnesses/$label-l.sens" "$TMP/witnesses/$label-r.sens" \
      "$TMP/repeat-$label-$mode.elf" >/dev/null
    cmp "$ELF" "$TMP/repeat-$label-$mode.elf"
    if [[ -v SENS_ORACLE_BIN ]]; then
      test -x "$SENS_ORACLE_BIN"
      test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
      printf '(%s %s %s)\n' "$opname" "$left" "$right" >"$TMP/oracle.lisp"
      timeout 60s "$SENS_ORACLE_BIN" "$TMP/oracle.lisp" \
        >"$TMP/oracle.out" 2>"$TMP/oracle.err" || {
          cat "$TMP/oracle.err" >&2; exit 1; }
      test ! -s "$TMP/oracle.err"
      python3 - "$TMP/oracle.out" "$answer" <<'PY'
from pathlib import Path
import sys
raw=Path(sys.argv[1]).read_text(encoding='utf-8').strip()
if raw.startswith('sens[укр]> '): raw=raw[len('sens[укр]> '):].strip()
projection={'1':'ТАК','0':'НІ','ТАК':'ТАК','НІ':'НІ','(т а к)':'ТАК','(н і)':'НІ'}
assert raw in projection and projection[raw]==sys.argv[2],f'D6 oracle: {raw!r}'
PY
      ORACLE=$((ORACLE+1))
    fi
    COUNT=$((COUNT+1))
  done
done < "$TMP/matrix.tsv"
test "$COUNT" -eq 24
if [[ -v SENS_ORACLE_BIN ]]; then test "$ORACLE" -eq 24; fi
# Відмови без створення виходу чи часткового stdout.
NEG=0
reject() {
 local out="$TMP/reject-$NEG.elf"
 if timeout 10s "$TMP/bin/sensd6mezhyelf" "$@" "$out" \
    >"$TMP/reject.stdout" 2>"$TMP/reject.err"; then
   echo "Д6-МЕЖІ-ПОМИЛКА: допущено негатив $NEG" >&2; exit 1
 fi
 test ! -e "$out" && test ! -s "$TMP/reject.stdout"
 grep -Fq 'ЕЛФ-Д6-МЕЖІ-ВІДМОВА:' "$TMP/reject.err"
 NEG=$((NEG+1))
}
L="$TMP/witnesses/06-l.sens"; R="$TMP/witnesses/06-r.sens"
for mode in --D6-110100 --D6-110110; do
  for bad in bad1 bad7 bad24 corrupt empty; do
    reject "$mode" "$TMP/witnesses/$bad.sens" "$R"
  done
done
reject --D6-110111 "$L" "$R"
reject --D6-110100 "$TMP/not-found.sens" "$R"
cp "$L" "$TMP/text.lisp"
reject --D6-110100 "$TMP/text.lisp" "$R"
reject --D6-110110 "$L" "$TMP/witnesses/bad24.sens"
test "$NEG" -eq 14
# No-clobber й recovery без послаблення перевірки.
cp "$TMP/06-110100.elf" "$TMP/occupied.elf"
if timeout 10s "$TMP/bin/sensd6mezhyelf" --D6-110100 "$L" "$R" \
  "$TMP/occupied.elf" >"$TMP/reject.stdout" 2>"$TMP/reject.err"; then
  echo 'Д6-МЕЖІ-ПОМИЛКА: перезаписано ELF' >&2; exit 1
fi
test ! -s "$TMP/reject.stdout"
cmp "$TMP/06-110100.elf" "$TMP/occupied.elf"
timeout 10s "$TMP/bin/sensd6mezhyelf" --D6-110100 "$L" "$R" \
  "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/06-110100.elf" "$TMP/recovered.elf"
echo "Д6-МЕЖІ-ELF-ПРОЙДЕНО physical=$COUNT oracle=$ORACLE негативів=$NEG SETLE/SETGE=так no-clobber=так енергія=НЕ-ВИМІРЯНО"
