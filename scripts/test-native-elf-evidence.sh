#!/usr/bin/env bash
# G6.151 — реальний FPC→ELF64→виконання→побайтовий фізичний доказ.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in git fpc timeout python3 mktemp cmp grep; do
  command -v "$tool" >/dev/null || { echo "ELF-ДОКАЗ-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/data"
timeout 60s python3 scripts/test-native-elf-evidence.py >"$TMP/python.log" 2>&1 || {
  cat "$TMP/python.log" >&2; exit 1;
}
for spec in 'scripts/test-sensmashyna.pas:test-sensmashyna' \
            'src/sensmashyna.lpr:sensmashyna'; do
  IFS=: read -r source name <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-sensmashyna" "$ROOT/external/sens" "$TMP/data" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
test ! -s "$TMP/fixtures.err"
count=0
for spec in 'тотожність:тотожні-00' 'атом:атом-пара' 'цитата:цитата-список'; do
  IFS=: read -r mode name <<< "$spec"
  source="$TMP/data/$name.sens"
  expected="$TMP/data/$name.expected.sens"
  machine="$TMP/$name.elf"
  report="$TMP/$name.json"
  test -s "$source" && test -s "$expected"
  timeout 20s "$TMP/bin/sensmashyna" "--$mode" "$ROOT/external/sens" \
    "$source" "$machine" >"$TMP/$name.compile.log" 2>"$TMP/$name.compile.err"
  test ! -s "$TMP/$name.compile.err"
  test -x "$machine"
  timeout 10s python3 scripts/native-elf-evidence.py \
    --джерело "$source" --машина "$machine" --очікувано "$expected" \
    --звіт "$report" >"$TMP/$name.audit.log" 2>"$TMP/$name.audit.err"
  test ! -s "$TMP/$name.audit.err"
  grep -Fq 'НАТИВНИЙ-ELF-ДОКАЗ:' "$TMP/$name.audit.log"
  timeout 5s python3 - "$source" "$machine" "$expected" "$report" <<'PY'
import hashlib,json,sys
from pathlib import Path
s,m,e,r=map(Path,sys.argv[1:])
p=json.loads(r.read_text(encoding='utf-8'))
assert p['схема']=='sens-native-elf-execution/1'
assert p['джерело_sha256']==hashlib.sha256(s.read_bytes()).hexdigest()
assert p['elf_sha256']==hashlib.sha256(m.read_bytes()).hexdigest()
assert p['очікуване_sha256']==hashlib.sha256(e.read_bytes()).hexdigest()
assert p['виконане_sha256']==p['очікуване_sha256']
assert p['енергія']=='ENERGY_NOT_MEASURED'
assert p['семантичний_оракул']=='НЕ_ПЕРЕВІРЕНО'
PY
  count=$((count+1))
done
test "$count" -eq 3
# Неправильний фізичний результат НЕ публікує часткового звіту.
printf '\377' >"$TMP/wrong.sens"
rc=0
timeout 10s python3 scripts/native-elf-evidence.py \
  --джерело "$TMP/data/тотожні-00.sens" \
  --машина "$TMP/тотожні-00.elf" \
  --очікувано "$TMP/wrong.sens" \
  --звіт "$TMP/rejected.json" >"$TMP/rejected.log" 2>"$TMP/rejected.err" || rc=$?
test "$rc" -eq 2
test ! -e "$TMP/rejected.json" && test ! -s "$TMP/rejected.log"
grep -Fq 'НАТИВНИЙ-ELF-ВІДМОВА:' "$TMP/rejected.err"
echo "НАТИВНИЙ-ELF-ДОКАЗ-ГАРАЗД fpc=checked native=$count negative=1 bytes=exact oracle=NOT-CHECKED energy=NOT-MEASURED"
