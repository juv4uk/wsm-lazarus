#!/usr/bin/env bash
# G6.102 — фізичний D12 stdin до двох D6 машинних предикатів, exact D1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д6-ПАРНІСТЬ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in timeout fpc mktemp readelf objdump cmp grep head tail seq dd git; do
  command -v "$cmd" >/dev/null || { echo "Д6-ПАРНІСТЬ-БЛОК: немає $cmd" >&2; exit 127; }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=$(git -C external/sens rev-parse HEAD)
test -n "$PIN"
grep -Fq '(010000 (ук парне?) (укр парне?)' external/sens/lib/domains/d6.lisp
grep -Fq '(010001 (ук непарне?) (укр непарне?)' external/sens/lib/domains/d6.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then for f in "$TMP/build.log" "$TMP/run.log" "$TMP/heap.log" "$TMP/oracle.out" "$TMP/oracle.err"; do [[ ! -s "$f" ]] || tail -n 60 "$f" >&2; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd6parnpotik "$ROOT/scripts/test-elfd6parnpotik.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-elfd6parnpotik" "$TMP/data" >"$TMP/run.log" 2>"$TMP/stderr.log" || {
  cat "$TMP/run.log" "$TMP/stderr.log" >&2; exit 1;
}
grep -Fq 'D6-PARITY-STREAM-BUILD-OK files=2 vectors=16 checks=32' "$TMP/run.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
PASS=0
for mode in parne neparne; do
  elf="$TMP/data/$mode.elf"
  chmod 700 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/$mode.elfheader"
  grep -Eq 'Type:.*DYN' "$TMP/$mode.elfheader"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$mode.elfheader"
  timeout 5s readelf -l "$elf" >"$TMP/$mode.segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$mode.segments"
  tail -c +121 "$elf" >"$TMP/$mode.code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$mode.code" >"$TMP/$mode.asm"
  grep -Eiq 'test[[:space:]]+al,0x1' "$TMP/$mode.asm"
  if [[ "$mode" == parne ]]; then
    grep -Eiq 'sete[[:space:]]+al' "$TMP/$mode.asm"
  else
    grep -Eiq 'setne[[:space:]]+al' "$TMP/$mode.asm"
  fi
  for n in $(seq -w 0 15); do
    timeout 5s "$elf" <"$TMP/data/$n.sens" \
      >"$TMP/got.sens" 2>"$TMP/err"
    test ! -s "$TMP/err"
    cmp "$TMP/got.sens" "$TMP/data/$n.$mode.sens"
    PASS=$((PASS+1))
  done
done
test "$PASS" -eq 32
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  ORACLE=0
  oracle_index=0
  for number in 0 1 -1 2 -2 3 -3 17 -17 1024 -1024 2047 -2048 -2047 2046 -2046; do
    printf -v oracle_label "%02d" "$oracle_index"
    for mode in parne neparne; do
      if [[ "$mode" = parne ]]; then op='парне?'; else op='непарне?'; fi
      oracle_file="$TMP/data/$oracle_label.$mode.call.sens"
      test -s "$oracle_file"
      if ! timeout 60s "$SENS_ORACLE_BIN" "$oracle_file" >"$TMP/oracle.out" 2>"$TMP/oracle.err"; then
        echo "Д6-ПАРНІСТЬ-ОРАКУЛ: REPL повернув помилку для $op $number" >&2
        cat "$TMP/oracle.out" "$TMP/oracle.err" >&2; exit 1
      fi
      if [[ -s "$TMP/oracle.err" ]]; then
        echo "Д6-ПАРНІСТЬ-ОРАКУЛ: стороння діагностика у stderr для $op $number" >&2
        cat "$TMP/oracle.err" >&2; exit 1
      fi
      awk '
        { sub(/\r$/, ""); sub(/[ \t]+$/, ""); line=$0
          sub(/^sens\[укр\]> /, "", line)
          if (line ~ /(ПОМИЛКА|помилка|ERROR|Error|error)/) bad=1
          if (line ~ /^\([ \t]*т[ \t]+а[ \t]+к[ \t]*\)$/) line="ТАК"
          if (line ~ /^\([ \t]*н[ \t]+і[ \t]*\)$/) line="НІ"
          if (line=="1") line="ТАК"
          if (line=="0") line="НІ"
          if (line=="ТАК" || line=="НІ") {print line; n++}
        }
        END {if (bad || n!=1) exit 48}
      ' "$TMP/oracle.out" >"$TMP/oracle.norm" || {
        echo "Д6-ПАРНІСТЬ-ОРАКУЛ: неприпустима відповідь $mode $number" >&2
        cat "$TMP/oracle.out" >&2; exit 1
      }
      if (( number % 2 == 0 )); then
        if [[ "$mode" == parne ]]; then wanted=ТАК; else wanted=НІ; fi
      else
        if [[ "$mode" == parne ]]; then wanted=НІ; else wanted=ТАК; fi
      fi
      printf '%s\n' "$wanted" >"$TMP/oracle.expected"
      cmp "$TMP/oracle.norm" "$TMP/oracle.expected" || {
        echo "Д6-ПАРНІСТЬ-ОРАКУЛ: розбіжність $mode $number" >&2
        cat "$TMP/oracle.out" >&2; exit 1
      }
      ORACLE=$((ORACLE+1))
    done
    oracle_index=$((oracle_index+1))
  done
  test "$ORACLE" -eq 32
  echo "D6-PARITY-ORACLE-OK pinned=$PIN checks=$ORACLE"
fi
NEG=0
reject() {
  local src="$1"
  for mode in parne neparne; do
    if timeout 5s "$TMP/data/$mode.elf" <"$src" \
      >"$TMP/reject.out" 2>"$TMP/reject.err"; then
      echo "Д6-ПАРНІСТЬ-ПОМИЛКА: недійсний T5M прийнято: $src" >&2; exit 1
    else
      rc=$?
      test "$rc" -eq 2 || { echo "хибний код відмови: $rc" >&2; exit 1; }
    fi
    test ! -s "$TMP/reject.out"
    grep -Fq 'Д6-ПАРНІСТЬ-ПОТІК-ВІДМОВА' "$TMP/reject.err"
    NEG=$((NEG+1))
  done
}
: >"$TMP/empty"; reject "$TMP/empty"
head -c 1 "$TMP/data/00.sens" >"$TMP/short1"; reject "$TMP/short1"
head -c 2 "$TMP/data/00.sens" >"$TMP/short2"; reject "$TMP/short2"
cp "$TMP/data/00.sens" "$TMP/surplus"; printf '\000' >>"$TMP/surplus"; reject "$TMP/surplus"
cp "$TMP/data/00.sens" "$TMP/invalid"; printf '\377' | dd of="$TMP/invalid" bs=1 seek=2 conv=notrunc status=none; reject "$TMP/invalid"
cp "$TMP/data/00.sens" "$TMP/invalidfirst"; printf '\377' | dd of="$TMP/invalidfirst" bs=1 seek=0 conv=notrunc status=none; reject "$TMP/invalidfirst"
cp "$TMP/data/00.sens" "$TMP/padding"; printf '\000' | dd of="$TMP/padding" bs=1 seek=2 conv=notrunc status=none; reject "$TMP/padding"
for mode in parne neparne; do
  { head -c 1 "$TMP/data/00.sens"; sleep 0.05;
    tail -c +2 "$TMP/data/00.sens"; } | timeout 5s "$TMP/data/$mode.elf" \
      >"$TMP/chunked.sens"
  cmp "$TMP/chunked.sens" "$TMP/data/00.$mode.sens"
done
test "$NEG" -eq 14
echo "D6-PARITY-STREAM-OK physical=32 negative=14 fragmented=2 isa=test-sete-setne energy=NOT-MEASURED"
