#!/usr/bin/env bash
# G6: профіль ізольованих фаз першої компіляції, жодних production правок.
# Усі 16 фізичних програм різні; ELF запускаємо на реальному x86-64 CPU.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ФАЗИ-WIDEIR-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for cmd in fpc git timeout readelf python3 cmp mktemp;do
  command -v "$cmd" >/dev/null || {
    echo "ФАЗИ-WIDEIR-БЛОК: немає $cmd" >&2;exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
cleanup(){
  local rc=$? f
  if ((rc!=0));then
    echo "ФАЗИ-WIDEIR-ПРОВАЛ exit=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures" "$TMP/elf"
for spec in \
 'scripts/test-irwidefront.pas test-irwidefront' \
 'scripts/profile-wideir-phases-first.pas profile-wideir-phases-first';do
  read -r src name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 35s "$TMP/bin/test-irwidefront" "$TMP/fixtures" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.log"
timeout 390s "$TMP/bin/profile-wideir-phases-first" \
  external/sens "$TMP/fixtures" "$TMP/elf" "$TMP/profile.json" \
  >"$TMP/profile.log" 2>"$TMP/profile.err"
grep -Fxq 'ФАЗИ-WIDEIR-ГАРАЗД cases=16 rounds=4 raw=64 elf-identical=yes negatives=2 recovery=2 oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/profile.log"
grep -Fq 'ФАЗИ-WIDEIR-МЕДІАНИ-НС t5m=' "$TMP/profile.log"
python3 - "$TMP/profile.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p["mode"]=="FIRST_DISTINCT_NO_OUTPUT_CACHE"
assert p["host"]=="MONOTONIC_IN_PROCESS" and p["non_additive"] is True
assert p["energy"]=="NOT_MEASURED" and p["cold_process"]=="NOT_MEASURED"
assert p["independent_sens_oracle"]=="NOT_MEASURED"
rows=p["raw_ns"]
assert p["sample_count"]==64 and len(rows)==64
names=[f"{n:02d}" for n in range(1,17)]
keys=["t5m_decode_encode_ns","pinned_load_ns","wideir_build_ns",
      "wideir_verify_ns","full_compiler_ns"]
for cycle in range(4):
    sub=rows[16*cycle:16*(cycle+1)]
    assert [x["case"] for x in sub]==names
    assert {x["cycle"] for x in sub}=={cycle}
for row in rows:
    assert all(isinstance(row[k],int) and row[k]>=0 for k in keys)
for k in keys:
    durations=sorted(row[k] for row in rows)
    assert p["median_ns"][k]==durations[31]+(durations[32]-durations[31])//2
print('ФАЗИ-WIDEIR-JSON-ГАРАЗД raw=64 phases=5 nonadditive=yes')
PY
for i in $(seq -w 1 16);do
  exe="$TMP/elf/$i.elf"
  chmod 0700 "$exe"
  test -s "$exe"
  readelf -h "$exe" >"$TMP/elf-header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf-header.log"
  timeout 8s "$exe" >"$TMP/$i.actual.sens" 2>"$TMP/$i.run.err"
  test ! -s "$TMP/$i.run.err"
  cmp "$TMP/$i.actual.sens" "$TMP/fixtures/$i.expected.sens"
done
if [[ -n "$(printenv SENS_STAGE_PROFILE_DEST || true)" ]];then
  cp "$TMP/profile.json" "$(printenv SENS_STAGE_PROFILE_DEST)"
fi
cat "$TMP/profile.log"
echo 'ФАЗИ-WIDEIR-ELF-ПІДТВЕРДЖЕНО real=16 positive=16 negative=2 cold-process=NOT-MEASURED speedup=NOT_CLAIMED'
