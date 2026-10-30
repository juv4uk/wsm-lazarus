#!/usr/bin/env bash
# G6.170 — 25×3×20 холодних нативних запусків, без Rust/Zig у CI.
# Мовний oracle: pinned G6.161 (цей тест НЕ додає мовної семантики).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д5-ЧАСТКА-COLD-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for x in fpc gcc python3 git timeout cmp readelf grep mktemp;do
  command -v "$x" >/dev/null || { echo "Бракує $x" >&2;exit 127; }
done
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show "$PIN:lib/domains/d5.lisp" |
  grep -Fq '(10111 (ук частка) (укр частка)'
TMP=$(mktemp -d)
cleanup(){
  local rc=$? f
  if ((rc!=0));then
    echo "Д5-ЧАСТКА-COLD-ПРОВАЛ: рядок=$1 код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'cleanup "$LINENO"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/frames"
python3 scripts/benchmark-d5-chastka-cold.py --selftest |
  grep -Fq 'негативів=11'
for spec in \
 'src/sensd12quotpotikelf.lpr sensd12quotpotikelf' \
 'scripts/test-elfd12quotpotik.pas test-elfd12quotpotik';do
  read -r src name <<<"$spec"
  timeout 180s fpc -B -Cr -Co -Ci -Mobjfpc -O2 -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name-build.log" 2>&1 || {
      cat "$TMP/$name-build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
HEAPTRC="log=$TMP/fixture-heap.log" timeout 30s \
 "$TMP/bin/test-elfd12quotpotik" "$TMP/frames" \
 >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'positive=25 numeric-reject=7 frame-reject=11' "$TMP/fixtures.log"
if grep -Fq 'unfreed memory blocks' "$TMP/fixture-heap.log";then
  grep -Fq '0 unfreed memory blocks' "$TMP/fixture-heap.log"
fi
HEAPTRC="log=$TMP/compiler-heap.log" timeout 30s \
 "$TMP/bin/sensd12quotpotikelf" --зібрати-D5-частку-потік \
 "$TMP/frames/anchor.sens" "$TMP/chastka.elf" \
 >"$TMP/compile.log" 2>"$TMP/compile.err"
test -x "$TMP/chastka.elf"
grep -Fq 'machine=CDQ_IDIV_R9D' "$TMP/compile.log"
if grep -Fq 'unfreed memory blocks' "$TMP/compiler-heap.log";then
  grep -Fq '0 unfreed memory blocks' "$TMP/compiler-heap.log"
fi
readelf -h "$TMP/chastka.elf" >"$TMP/header.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
! readelf -l "$TMP/chastka.elf" | grep -Eq 'INTERP|DYNAMIC'
REPEATS=$(printenv SENS_D5_COLD_REPEATS || echo 20)
timeout 900s python3 scripts/benchmark-d5-chastka-cold.py \
  --root "$ROOT" --fixtures "$TMP/frames" \
  --sens-elf "$TMP/chastka.elf" --work "$TMP/results" \
  --repeat "$REPEATS" --seed 170170 >"$TMP/bench.log" \
  2>"$TMP/bench.err" || {
    cat "$TMP/bench.err" >&2;exit 1;
  }
grep -Fq "D5-ЧАСТКА-COLD-ГОТОВО binaries=3 cases=25 negatives=54 runs=$((REPEATS*75)) energy=NOT_MEASURED" \
  "$TMP/bench.log"
python3 - "$TMP/results/виміри.json" "$REPEATS" <<'PY'
import collections,json,sys
with open(sys.argv[1],encoding='utf-8') as inp:
    r=json.load(inp)
repeats=int(sys.argv[2])
assert r['схема']=='sens-d5-chastka-cold/1'
assert r['pinned_sens']=='1f1bf676eeac605e065035d9dd2adaae807f1788'
assert r['позитивів_перед_замірами']==75
assert r['негативів_перед_замірами']==54
assert r['енергія']=='ENERGY_NOT_MEASURED'
assert r['повторів_на_випадок']==repeats
samples=r['сирі_виміри']
assert len(samples)==repeats*25*3
assert len(r['виконувані_SHA256'])==3
assert set(r['виконувані_SHA256'])=={'sens-elf','c-gcc','free-pascal'}
assert all(len(x)==64 for x in r['виконувані_SHA256'].values())
assert all(x['час_нс']>0 for x in samples)
counts=collections.Counter((x['випадок'],x['виконавець']) for x in samples)
assert len(counts)==75 and set(counts.values())=={repeats}
assert all(x['кількість']==repeats*25 for x in r['підсумки'].values())
assert len(r['виконувані_розміри'])==3
assert all(v>100 for v in r['виконувані_розміри'].values())
print('Д5-ЧАСТКА-COLD-ЗВІТ-ПЕРЕВІРЕНО samples=%d energy=NOT_MEASURED'%len(samples))
PY
mkdir -p "$ROOT/build/m0.2/d5-chastka-cold"
cp "$TMP/results/виміри.json" "$ROOT/build/m0.2/d5-chastka-cold/виміри.json"
test -s "$ROOT/build/m0.2/d5-chastka-cold/виміри.json"
echo "Д5-ЧАСТКА-COLD-МЕХАНІЧНО-ГОТОВО validations=75 negatives=54 timed=$((REPEATS*75)) rust=0 zig=0 joules=NOT_MEASURED"
