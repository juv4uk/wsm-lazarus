#!/usr/bin/env bash
# G6.195: A/B compiler only, real checked FPC + 16 x86-64 PIE executions.
# Full raw host timings, no energy or fabricated minimum speedup.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for t in fpc git timeout python3 cmp readelf mktemp grep sha256sum;do
  command -v "$t" >/dev/null || { echo "VERIFIEDZERO-AB-BLOCK: $t" >&2;exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
grep -Fq '(01000 (ук нуль?) (укр нуль?)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
cleanup(){
  local status=$? item
  if (( status!=0 ));then
    echo "VERIFIEDZERO-AB-FAIL rc=$status" >&2
    for item in "$TMP"/*.log "$TMP"/*.err;do
      [[ ! -s "$item" ]] || { echo "--- $item" >&2;tail -n 35 "$item" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/elf"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -obenchmark-verifiedzero-first \
  "$ROOT/scripts/benchmark-verifiedzero-first.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2;exit 1; }
test -x "$TMP/bin/benchmark-verifiedzero-first"
timeout 650s "$TMP/bin/benchmark-verifiedzero-first" \
  external/sens "$TMP/elf" "$TMP/report.json" \
  >"$TMP/benchmark.log" 2>"$TMP/benchmark.err"
grep -Fq 'forms=16 samples=64 legacy=64 verified=64 negatives=4 recovery=8 parity=identical' "$TMP/benchmark.log"
grep -Fq ' legacy_ns=' "$TMP/benchmark.log"
grep -Fq '0 unfreed memory blocks' "$TMP/benchmark.err"
python3 - "$TMP/report.json" <<'PY'
import json,statistics,sys
p=json.load(open(sys.argv[1],encoding="utf8"))
assert p["mode"]=="FIRST_NEW_PROGRAM_PERSISTENT_HOST"
assert p["energy"]=="NOT_MEASURED"
assert p["cold_process"]=="NOT_MEASURED"
assert p["sens_oracle"]=="NOT_CHECKED"
rows=p["raw_ns"]
assert len(rows)==64 and p["count"]==64
for cycle in range(4):
  a=rows[cycle*16:(cycle+1)*16]
  assert [x["case"] for x in a]==[f"{i:02d}" for i in range(1,17)]
  assert {x["cycle"] for x in a}=={cycle}
for key,med in [("legacy_ns","median_legacy_ns"),
                ("verified_ns","median_verified_ns")]:
  nums=[r[key] for r in rows]
  assert all(isinstance(n,int) and n>0 for n in nums)
  assert p[med]==int(statistics.median(nums))
ratio=p["median_legacy_ns"]/p["median_verified_ns"]
assert 0 < ratio < 100000
print(f"VERIFIEDZERO-AB-MEASURED legacy_ns={p['median_legacy_ns']} verified_ns={p['median_verified_ns']} observed_ratio={ratio:.4f} no_threshold=yes")
PY
for n in $(seq -w 1 16);do
  exe="$TMP/elf/$n.elf"
  chmod 0700 "$exe"
  readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 8s "$exe" >"$TMP/$n.actual.sens" 2>"$TMP/$n.err"
  test ! -s "$TMP/$n.err"
  cmp "$TMP/$n.actual.sens" "$TMP/elf/$n.expected.sens"
done
if [[ -n "$(printenv SENS_AB_REPORT_DEST || true)" ]];then
  cp "$TMP/report.json" "$(printenv SENS_AB_REPORT_DEST)"
fi
cat "$TMP/benchmark.log"
echo 'VERIFIEDZERO-AB-MACHINE-OK native=16 parity=all samples=64 negative=4 recovery=8 oracle=NOT_CHECKED energy=NOT_MEASURED'
