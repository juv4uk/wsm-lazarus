#!/usr/bin/env bash
# G6.104: реальний FPC/ELF проти C/Rust/FPC на ТИХ САМИХ D12 байтах.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D12-COLD-BLOCK: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc gcc rustc python3 timeout mktemp git cmp readelf; do
  command -v "$tool" >/dev/null || { echo "D12-COLD-BLOCK: немає $tool" >&2; exit 127; }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if (( rc != 0 )); then
  echo "D12-COLD-FAIL: code=$rc" >&2
  for log in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 35 "$log" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/frames"
python3 scripts/benchmark-d12-stdin-cold.py --selftest
for row in \
  'src/sensd12potikelf.lpr sensd12potikelf' \
  'scripts/test-elfd12potik.pas test-elfd12potik'; do
  read -r source executable <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/build-$executable.log" 2>&1 || {
      cat "$TMP/build-$executable.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$executable"
done
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-elfd12potik" \
  "$TMP/frames" >"$TMP/frames/valid.tsv" 2>"$TMP/generator.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test "$(wc -l <"$TMP/frames/valid.tsv")" -eq 13
grep -Fq 'позитивів=13' "$TMP/generator.err"
timeout 15s "$TMP/bin/sensd12potikelf" --зібрати-D12-потік \
  "$TMP/d12.elf" >"$TMP/compile.log" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err"
test -x "$TMP/d12.elf"
readelf -h "$TMP/d12.elf" >"$TMP/elf-header.log"
grep -Eq 'Type:.*DYN' "$TMP/elf-header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf-header.log"
timeout 750s python3 scripts/benchmark-d12-stdin-cold.py \
  --root "$ROOT" --fixtures "$TMP/frames" --sens-elf "$TMP/d12.elf" \
  --work "$TMP/report" --repeat "$(printenv SENS_D12_COLD_REPEATS || printf 30)" \
  --seed 104104 >"$TMP/benchmark.log" 2>"$TMP/benchmark.err" || {
    cat "$TMP/benchmark.err" >&2; exit 1;
  }
grep -Fq 'D12-COLD-OK binaries=4 cases=13 negatives=60 runs=1560' \
  "$TMP/benchmark.log"
python3 - "$TMP/report/виміри.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as stream:
    r=json.load(stream)
assert r['схема']=='sens-d12-stdin-cold-compare/1'
assert r['енергія']=='ENERGY_NOT_MEASURED'
assert r['позитивів_перед_замірами']==52
assert r['негативів_перед_замірами']==60
assert len(r['підсумки'])==52
assert len(r['сирі_виміри'])==1560
assert len(r['виконувані_SHA256'])==4
assert {x['виконавець'] for x in r['сирі_виміри']}=={
  'sens-elf','c-gcc','rust','free-pascal'}
assert all(x['час_нс']>0 for x in r['сирі_виміри'])
PY
echo 'D12-COLD-MACHINE-OK physical=13x4 negative=15x4 timed=1560'
