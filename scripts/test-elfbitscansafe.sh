#!/usr/bin/env bash
# G6.134 — host D12 фізичний тест, не нова мовна функція SENS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'BSF-BSR-ЗАХИСТ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc readelf objdump cmp mktemp awk; do
  command -v "$tool" >/dev/null || {
    echo "BSF-BSR-ЗАХИСТ-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then
  for f in "$TMP"/*.log; do [[ ! -s "$f" ]] || {
    echo "--- $f" >&2; tail -n 60 "$f" >&2; }
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfbitscansafe "$ROOT/scripts/test-elfbitscansafe.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 45s \
  "$TMP/bin/test-elfbitscansafe" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'BSF-BSR-ЗАХИСТ-ГОТОВО physical-D12=8 machine-ELF=16 positive=14 zero-exit2=2 negative=6 repeat=16 energy=NOT-MEASURED' "$TMP/test.log"
test ! -s "$TMP/stderr.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log" || {
  cat "$TMP/heap.log" >&2; exit 1;
}
POS=0;ZEROS=0;CLOSED=0;FULL=0;RECOVERED=0
for i in 0 1 2 3 4 5 6 7; do
  for kind in 0 1; do
    prefix="$TMP/data/case-$i-$kind"
    elf="$prefix.elf"
    chmod 700 "$elf"
    cmp "$elf" "$prefix.again.elf"
    timeout 5s readelf -h "$elf" >"$TMP/header.log"
    grep -Eq 'Type:.*DYN' "$TMP/header.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
    timeout 5s readelf -l "$elf" >"$TMP/segments.log"
    ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
    tail -c +121 "$elf" >"$TMP/instructions"
    timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/instructions" >"$TMP/disassembly.log"
    # Інструкційне свідчення TEST -> JZ/JE -> BSF/BSR.
    if [[ "$kind" -eq 0 ]]; then opcode=bsf; else opcode=bsr; fi
    # Перевіряємо що *машина* виконує перевірку результату запису.
  grep -Eq 'cmp[[:space:]]+eax,edx' "$TMP/disassembly.log"
  grep -Eq 'sete[[:space:]]+al' "$TMP/disassembly.log"
  grep -Eq 'movzx[[:space:]]+eax,al' "$TMP/disassembly.log"
  awk -v opcode="$opcode" '
      /test[[:space:]]+eax,eax/ && !t {t=NR}
      /je[[:space:]]/ && !j {j=NR}
      $0 ~ opcode"[[:space:]]" && !b {b=NR}
      END {exit !(t>0 && j>t && b>j)}' "$TMP/disassembly.log"
    rc=0
    timeout 5s "$elf" >"$TMP/answer.sens" 2>"$TMP/answer.err" || rc=$?
    test ! -s "$TMP/answer.err"
    if [[ "$i" -eq 0 ]]; then
      test "$rc" -eq 2
      test ! -s "$TMP/answer.sens"
      ZEROS=$((ZEROS+1))
    else
      test "$rc" -eq 0
      cmp "$TMP/answer.sens" "$prefix.expected.sens"
      POS=$((POS+1))
      # Linux -EBADF: stdout справді закритий, а не перенаправлений.
      rc=0
      timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$elf" \
        2>"$TMP/closed.err" || rc=$?
      test "$rc" -eq 2
      test ! -s "$TMP/closed.err"
      CLOSED=$((CLOSED+1))
      # Linux -ENOSPC: /dev/full існує на ubuntu-24.04.
      rc=0
      timeout 5s "$elf" > /dev/full 2>"$TMP/full.err" || rc=$?
      test "$rc" -eq 2
      test ! -s "$TMP/full.err"
      FULL=$((FULL+1))
      # Той самий ELF повинен працювати після обох негативів.
      rc=0
      timeout 5s "$elf" >"$TMP/recovered.sens" \
        2>"$TMP/recovered.err" || rc=$?
      test "$rc" -eq 0
      test ! -s "$TMP/recovered.err"
      cmp "$TMP/recovered.sens" "$prefix.expected.sens"
      RECOVERED=$((RECOVERED+1))
    fi
  done
done
test "$POS" -eq 14
test "$ZEROS" -eq 2
test "$CLOSED" -eq 14
test "$FULL" -eq 14
test "$RECOVERED" -eq 14
echo 'BSF-BSR-WRITE-PASS positives=14 closed=14 full=14 recovery=14 machine=CMP-SETE-MOVZX oracle=NOT-RUN energy=NOT-MEASURED'
echo 'BSF-BSR-ЗАХИСТ-МАШИНА-ГАРАЗД D12=8 ELF64=16 positives=14 zero=2 negatives=6 T5M=byte-exact energy=NOT-MEASURED'
