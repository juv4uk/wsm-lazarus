#!/usr/bin/env bash
# G6.96 — D12 numeric admission старого backend, реальний машинний
# ADD eax,ecx у новому, byte-exact T5M, а не precomputed output.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-REG-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for bin in fpc timeout readelf objdump cmp mktemp; do
  command -v "$bin" >/dev/null || { echo "D12-REG-БЛОК: немає $bin" >&2; exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 60 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
for spec in "scripts/test-elfd12add.pas:test-elfd12add" \
            "scripts/test-elfd12addreg.pas:test-elfd12addreg"; do
  IFS=: read -r src name <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2; exit 1;
    }
done
HEAPTRC="log=$TMP/fixtures.heap" timeout 15s \
  "$TMP/bin/test-elfd12add" "$TMP/data" >"$TMP/fixtures.log" 2>"$TMP/fixtures.err.log"
HEAPTRC="log=$TMP/reg.heap" timeout 20s \
  "$TMP/bin/test-elfd12addreg" "$TMP/data" >"$TMP/reg.log" 2>"$TMP/reg.err.log" || {
    cat "$TMP/reg.err.log" "$TMP/reg.log" >&2; exit 1;
  }
grep -Fq 'D12-ALU-REG-ГОТОВО ELF=9 negative=12 invariant=TAIL-EXACT' "$TMP/reg.log"
for heap in "$TMP/fixtures.heap" "$TMP/reg.heap"; do
  test -s "$heap"
  grep -Fq '0 unfreed memory blocks' "$heap"
done
for i in 01 02 03 04 05 06 07 08 09; do
  new="$TMP/data/$i-reg.elf"; old="$TMP/data/$i-old.elf"
  chmod 700 "$new" "$old"
  readelf -h "$new" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  readelf -l "$new" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$new" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/asm.log"
  grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/asm.log"
  timeout 5s "$new" >"$TMP/new.sens"
  timeout 5s "$old" >"$TMP/old.sens"
  cmp "$TMP/new.sens" "$TMP/old.sens"
  cmp "$TMP/new.sens" "$TMP/data/$i-expected.sens"
done
echo 'D12-REG-МАШИНА-ГАРАЗД ELF=9 old-parity=9 canonical-T5M=9 negative=12 energy=NOT-MEASURED'
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  oracle=0
  for row in '01:0:0:0' '02:31:42:73' '03:-12:7:-5' \
             '04:-1024:-1024:-2048' '05:-2048:2047:-1' \
             '06:1023:1:1024' '07:2047:-2048:-1' \
             '08:2046:1:2047' '09:-2047:-1:-2048'; do
    IFS=: read -r label left right wanted <<< "$row"
    printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.wanted"
    cmp "$TMP/$label.oracle" "$TMP/$label.wanted"
    oracle=$((oracle+1))
  done
  test "$oracle" -eq 9
  echo "D12-REG-НЕЗАЛЕЖНИЙ-SENS-ГАРАЗД pinned=$PIN oracle=$oracle"
fi
