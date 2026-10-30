#!/usr/bin/env bash
# G6.108: справжня FPC-механіка розподілу, машинний GNU as та pinned D5.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'РЕГІСТРИ-ЖИТТЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for bin in fpc git timeout as objcopy cmp readelf objdump mktemp grep; do
  command -v "$bin" >/dev/null || {
    echo "РЕГІСТРИ-ЖИТТЯ-БЛОК: немає $bin" >&2; exit 127; }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 70 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
for spec in 'scripts/test-elfd12add.pas:test-elfd12add' \
            'scripts/test-x64lifetimes.pas:test-x64lifetimes'; do
  IFS=: read -r src name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2; exit 1; }
done
HEAPTRC="log=$TMP/fixtures.heap" timeout 30s \
  "$TMP/bin/test-elfd12add" "$TMP/data" >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
HEAPTRC="log=$TMP/lifetimes.heap" timeout 90s \
  "$TMP/bin/test-x64lifetimes" "$TMP/data" >"$TMP/lifetimes.log" 2>"$TMP/lifetimes.err" || {
    cat "$TMP/lifetimes.err" "$TMP/lifetimes.log" >&2; exit 1; }
grep -Fq 'X64-LIFETIMES-OK interval=144 register-matrix=8 negative=12 physical-d5=9' "$TMP/lifetimes.log"
for f in "$TMP/fixtures.heap" "$TMP/lifetimes.heap"; do
  test -s "$f"
  grep -Fq '0 unfreed memory blocks' "$f"
done
timeout 30s as --64 -o "$TMP/allocator.o" "$TMP/data/allocator.s"
timeout 30s objcopy -O binary -j .text "$TMP/allocator.o" "$TMP/data/allocator.gnu.bin"
cmp "$TMP/data/allocator.gnu.bin" "$TMP/data/allocator.fpc.bin"
test "$(wc -c <"$TMP/data/allocator.gnu.bin")" -eq 80
for i in 01 02 03 04 05 06 07 08 09; do
  target="$TMP/data/$i.elf"
  test -s "$target"
  chmod 700 "$target"
  timeout 5s readelf -h "$target" >"$TMP/header-$i.log"
  grep -Eq 'Type:.*DYN' "$TMP/header-$i.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header-$i.log"
  timeout 5s readelf -l "$target" >"$TMP/segments-$i.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments-$i.log"
  tail -c +121 "$target" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/asm-$i.log"
  grep -Eq 'movabs[[:space:]]+r8,' "$TMP/asm-$i.log"
  grep -Eq 'movabs[[:space:]]+r9,' "$TMP/asm-$i.log"
  grep -Eq 'add[[:space:]]+r8,r9' "$TMP/asm-$i.log"
  timeout 5s "$target" >"$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/data/$i-expected.sens"
done
echo 'X64-LIFETIMES-МАШИНА-ГАРАЗД intervals=144 rexa=8 native-d5=9 negative=12 energy=NOT-MEASURED'
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
  oracle=0
  for row in '01:0:0:0' '02:31:42:73' '03:-12:7:-5' \
             '04:-1024:-1024:-2048' '05:-2048:2047:-1' \
             '06:1023:1:1024' '07:2047:-2048:-1' \
             '08:2046:1:2047' '09:-2047:-1:-2048'; do
    IFS=: read -r label left right wanted <<<"$row"
    printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.oracle.expected"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.oracle.expected"
    oracle=$((oracle+1))
  done
  test "$oracle" -eq 9
  echo "X64-LIFETIMES-PINNED-REPL-ГАРАЗД oracle=$oracle"
fi
