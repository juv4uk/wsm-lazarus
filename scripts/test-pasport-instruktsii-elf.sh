#!/usr/bin/env bash
# G6.158 — фактичний машинний перепис п'яти ELF64, не енергозамір і не оракул.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in python3 fpc git timeout objdump cmp mktemp grep; do
  command -v "$tool" >/dev/null || { echo "ВІДМОВА: потрібен $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ВІДМОВА: потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then
  echo "ІНСТРУКЦІЇ-ELF-ТЕСТ-ПРОВАЛ: код=$rc" >&2
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 25 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfgeometry "$ROOT/scripts/test-elfgeometry.pas" \
  >"$TMP/fpc.log" 2>"$TMP/fpc.err"
timeout 90s "$TMP/bin/test-elfgeometry" "$ROOT/external/sens" "$TMP/fixtures" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
count=0
for label in цитата-д7 атом-д1 тотожність-д1 перше-сполучення істинна-умова; do
  image="$TMP/fixtures/$label.elf"
  result="$TMP/$label.json"
  test -s "$image" && test -s "$TMP/fixtures/$label.expected.sens"
  timeout 20s python3 scripts/pasport-instruktsii-elf.py "$image" "$result" \
    >"$TMP/$label.log" 2>"$TMP/$label.err"
  grep -Fq 'енергія=НЕ_ВИМІРЯНО' "$TMP/$label.log"
  test ! -s "$TMP/$label.err"
  test -s "$result"
  python3 - "$image" "$result" <<'PY'
import hashlib, json, pathlib, sys
image=pathlib.Path(sys.argv[1]).read_bytes()
report=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
assert report['формат']=='ELF64-x86-64'
assert report['тип'] in ('PIE','EXEC')
assert report['байтів_elf']==len(image)
assert report['байтів_машини']+report['байтів_даних']==len(image)-120
assert report['байтів_машини']>=1 and report['байтів_даних']>=0
assert report['інструкцій']>=1
assert report['інструкцій']==sum(report['мнемоніки'].values())
assert 'syscall' in report['мнемоніки']
assert report['sha256_elf']==hashlib.sha256(image).hexdigest()
assert report['sha256_машини']==hashlib.sha256(image[120:120+report['байтів_машини']]).hexdigest()
assert report['sha256_даних']==hashlib.sha256(image[120+report['байтів_машини']:]).hexdigest()
assert report['енергія']=='НЕ_ВИМІРЯНО'
assert report['оракул_SENS']=='НЕ_ПЕРЕВІРЕНО'
PY
  timeout 20s python3 scripts/pasport-instruktsii-elf.py "$image" "$TMP/$label-repeat.json" \
    >"$TMP/repeat.log" 2>"$TMP/repeat.err"
  cmp "$result" "$TMP/$label-repeat.json"
  chmod u+x "$image"
  timeout 5s "$image" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$TMP/fixtures/$label.expected.sens"
  count=$((count+1))
done
test "$count" -eq 5

# Чотири пошкодження геометрії та остання неповна x86 інструкція.
python3 - "$TMP/fixtures/цитата-д7.elf" "$TMP" <<'PY'
from pathlib import Path
import sys
source=Path(sys.argv[1]).read_bytes()
directory=Path(sys.argv[2])
for name, position, value in (
    ('rwx', 68, 7), ('entry', 24, 119), ('kind', 16, 1),
):
    damaged=bytearray(source)
    damaged[position]=value
    (directory / f'bad-{name}.elf').write_bytes(damaged)
(directory / 'bad-short.elf').write_bytes(source[:-1])
other=directory / 'fixtures' / 'тотожність-д1.elf'
normal=other.read_bytes()
(directory / 'bad-machine-tail.elf').write_bytes(normal[:-1]+bytes([0x0f]))
PY
negatives=0
for bad in rwx entry kind machine-tail short; do
  target="$TMP/rejected-$bad.json"
  rc=0
  timeout 20s python3 scripts/pasport-instruktsii-elf.py \
    "$TMP/bad-$bad.elf" "$target" \
    >"$TMP/reject.log" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.log"
  grep -Fq 'ІНСТРУКЦІЇ-ELF-ВІДМОВА:' "$TMP/reject.err"
  negatives=$((negatives+1))
done
test "$negatives" -eq 5

# Наявний JSON і dangling symlink захищено атомарним O_EXCL-подібним link.
cp "$TMP/цитата-д7.json" "$TMP/occupied.json"
rc=0
timeout 20s python3 scripts/pasport-instruktsii-elf.py \
  "$TMP/fixtures/цитата-д7.elf" "$TMP/occupied.json" \
  >"$TMP/reject.log" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2
cmp "$TMP/occupied.json" "$TMP/цитата-д7.json"
ln -s "$TMP/does-not-exist.json" "$TMP/dangling.json"
rc=0
timeout 20s python3 scripts/pasport-instruktsii-elf.py \
  "$TMP/fixtures/цитата-д7.elf" "$TMP/dangling.json" \
  >"$TMP/reject.log" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2
test -L "$TMP/dangling.json" && test ! -e "$TMP/does-not-exist.json"
test ! -s "$TMP/reject.log"
echo "ІНСТРУКЦІЇ-ELF-ТЕСТ-ГАРАЗД FPC=реальний ELF=$count виконань=$count відмов=$negatives без-перезапису=2 енергія=НЕ_ВИМІРЯНО"
# Питання: чому machine-byte SHA не означає semantic parity SENS?
# Чому повторний JSON мусить збігтися до байта? Чому ELF виконуємо окремо?
# Чому п'ять ELF ще не означають довільний компілятор?
