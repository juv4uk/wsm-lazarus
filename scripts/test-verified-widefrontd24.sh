#!/usr/bin/env bash
# G6.266 — одна фізична D5/W24 програма → загальний і вузький CLI.
# Не копіює SENS закони/кодер: D24 fixtures породжує чинний FPC свідок.
# Один існуючий verified-all gate, без нових workflow/залежностей.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for tool in fpc git timeout cmp grep mktemp readelf stat wc tail python3; do
  command -v "$tool" >/dev/null || {
    echo "СПІЛЬНИЙ-D24-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
finish() {
  local rc=$? f
  if ((rc)); then
    echo "СПІЛЬНИЙ-D24-ПРОВАЛ code=$rc" >&2
    for f in "$TMP"/*.build.log "$TMP"/*.err "$TMP"/*.log; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for spec in \
 'scripts/test-irwided24carry.pas:test-irwided24carry' \
 'scripts/test-widefrontd24-negatives.pas:test-widefrontd24-negatives' \
 'src/senswidefrontelf.lpr:senswidefrontelf' \
 'src/sensirwided24elf.lpr:sensirwided24elf'; do
  IFS=: read -r source exe <<< "$spec"
  timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      tail -n 80 "$TMP/$exe.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/fixtures.heap" timeout 120s \
  "$TMP/bin/test-irwided24carry" "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'IR-D24-CARRY-OK positives=10 negative=12 recovery=1' "$TMP/fixtures.log"
test ! -s "$TMP/fixtures.err"
grep -Fq '0 unfreed memory blocks' "$TMP/fixtures.heap"
HEAPTRC="log=$TMP/negatives.heap" timeout 120s \
  "$TMP/bin/test-widefrontd24-negatives" "$ROOT/external/sens" \
  >"$TMP/negatives.log" 2>"$TMP/negatives.err"
grep -Fxq 'WIDEFRONT-D24-PAS-PASS positive=2 negative=12 recovery=1' "$TMP/negatives.log"
test ! -s "$TMP/negatives.err"
grep -Fq '0 unfreed memory blocks' "$TMP/negatives.heap"
PASS=0
while IFS=$'\t' read -r tag left right expected; do
  [[ "$tag" =~ ^[0-9][0-9]$ ]] || exit 1
  source="$TMP/physical/$tag.program.sens"
  common="$TMP/$tag.common.elf"
  narrow="$TMP/$tag.narrow.elf"
  HEAPTRC="log=$TMP/$tag.common.heap" timeout 50s \
    "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$source" "$common" >"$TMP/$tag.common.log" 2>"$TMP/$tag.common.err"
  HEAPTRC="log=$TMP/$tag.narrow.heap" timeout 50s \
    "$TMP/bin/sensirwided24elf" --скомпілювати-D24-форму \
    "$source" "$narrow" >"$TMP/$tag.narrow.log" 2>"$TMP/$tag.narrow.err"
  test ! -s "$TMP/$tag.common.err" && test ! -s "$TMP/$tag.narrow.err"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.common.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.narrow.heap"
  cmp "$common" "$narrow"
  cmp "$common" "$TMP/physical/$tag.elf"
  test "$(stat -c %a "$common")" = 700
  test "$(stat -c %a "$narrow")" = 700
  readelf -h "$common" >"$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  timeout 5s "$common" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.exec.err"
  test ! -s "$TMP/$tag.exec.err"
  test "$(wc -c < "$TMP/$tag.actual.sens")" -eq 5
  cmp "$TMP/$tag.actual.sens" "$TMP/physical/$tag.expected.sens"
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 10
# Повторний source provenance використовує той самий спільний compiler.
HEAPTRC="log=$TMP/provenance.heap" timeout 60s \
  "$TMP/bin/senswidefrontelf" --звірити-походження \
  "$TMP/physical/01.program.sens" "$TMP/01.common.elf" \
  >"$TMP/provenance.log" 2>"$TMP/provenance.err"
grep -Fq 'ЕЛЬФ-ПОХОДЖЕННЯ-ГАРАЗД' "$TMP/provenance.log"
test ! -s "$TMP/provenance.err"
# G6.268 — незалежні негативи перевірки походження ВЖЕ ГОТОВОГО ELF.
# Повторно використовуємо ті самі десять фізичних fixtures і одну FPC
# збірку: без нового workflow, закону, backend або зайвого компілювання.
# Навіть геометрично правильний ELF не стає доказом походження.
PROVENANCE_NEG=0
reject_provenance() {
  local tag="$1"; shift
  local rc=0
  HEAPTRC="log=$TMP/provenance-$tag.heap" timeout 60s \
    "$TMP/bin/senswidefrontelf" --звірити-походження "$@" \
    >"$TMP/provenance-$tag.out" 2>"$TMP/provenance-$tag.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/provenance-$tag.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/provenance-$tag.err"
  grep -Fq '0 unfreed memory blocks' "$TMP/provenance-$tag.heap"
  PROVENANCE_NEG=$((PROVENANCE_NEG+1))
}
# Підміна лише останнього байта не змінює ELF-заголовка, розміру чи entry;
# це тест саме рівності з pinned повторною збіркою, а не тільки geometry.
cp "$TMP/01.common.elf" "$TMP/provenance-tampered.elf"
python3 - "$TMP/provenance-tampered.elf" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
data = bytearray(p.read_bytes())
assert len(data) > 120
data[-1] ^= 1
p.write_bytes(data)
PY
cp "$TMP/provenance-tampered.elf" "$TMP/provenance-tampered.snapshot.elf"
! cmp -s "$TMP/01.common.elf" "$TMP/provenance-tampered.elf"
reject_provenance tampered "$TMP/physical/01.program.sens" "$TMP/provenance-tampered.elf"
cmp "$TMP/provenance-tampered.snapshot.elf" "$TMP/provenance-tampered.elf"
# Два коректні, але РІЗНІ фізичні джерела: чужий ELF не приймається.
! cmp -s "$TMP/physical/01.program.sens" "$TMP/physical/02.program.sens"
reject_provenance other-source "$TMP/physical/02.program.sens" "$TMP/01.common.elf"
cmp "$TMP/01.common.elf" "$TMP/physical/01.elf"
test "$PROVENANCE_NEG" -eq 2
# Відновлення: попередні відмови не псують перевірку чинного артефакту.
HEAPTRC="log=$TMP/provenance-recovered.heap" timeout 60s \
  "$TMP/bin/senswidefrontelf" --звірити-походження \
  "$TMP/physical/01.program.sens" "$TMP/01.common.elf" \
  >"$TMP/provenance-recovered.out" 2>"$TMP/provenance-recovered.err"
grep -Fq 'ЕЛЬФ-ПОХОДЖЕННЯ-ГАРАЗД' "$TMP/provenance-recovered.out"
test ! -s "$TMP/provenance-recovered.err"
grep -Fq '0 unfreed memory blocks' "$TMP/provenance-recovered.heap"
# Негативи самого CLI: відмова раніше за публікацію ELF.
NEG=0
reject() {
  local label="$1"; shift
  local target="$TMP/reject-$label.elf" rc=0
  timeout 40s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/reject-$label.out" 2>"$TMP/reject-$label.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/reject-$label.out" && test ! -e "$target"
  grep -Fq 'ВІДМОВА:' "$TMP/reject-$label.err"
  NEG=$((NEG+1))
}
: >"$TMP/empty.sens"
printf '\377' >"$TMP/bad.sens"
cp "$TMP/physical/01.program.sens" "$TMP/text.lisp"
reject empty --скомпілювати-фізичну-форму "$TMP/empty.sens"
reject corrupt --скомпілювати-фізичну-форму "$TMP/bad.sens"
reject extension --скомпілювати-фізичну-форму "$TMP/text.lisp"
reject mode --вигаданий-режим "$TMP/physical/01.program.sens"
test "$NEG" -eq 4
# Уже створений ELF не має бути перезаписаний.
rc=0
timeout 40s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
 "$TMP/physical/02.program.sens" "$TMP/01.common.elf" \
 >"$TMP/existing.out" 2>"$TMP/existing.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/existing.out"
cmp "$TMP/01.common.elf" "$TMP/physical/01.elf"
# Після всіх відмов той самий фізичний source дає той самий ELF.
timeout 50s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
 "$TMP/physical/01.program.sens" "$TMP/recovery.elf" \
 >"$TMP/recovery.log" 2>"$TMP/recovery.err"
test ! -s "$TMP/recovery.err"
cmp "$TMP/recovery.elf" "$TMP/01.common.elf"
timeout 5s "$TMP/recovery.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/01.expected.sens"
echo "VERIFIED-WIDEFRONT-D24-PASS FPC=checked physical=10 identical-ELF=10 executed=10 negative=$((12+NEG+1+PROVENANCE_NEG)) provenance-negative=$PROVENANCE_NEG recovery=1 D24=exact oracle=NOT-RUN energy=NOT-MEASURED"
