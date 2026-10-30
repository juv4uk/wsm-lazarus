#!/usr/bin/env bash
# G6: checked FPC O1/O2; same ELF as pinned D6 SUB1, machine execution.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for cmd in fpc timeout readelf objdump cmp grep mktemp dd git; do
  command -v "$cmd" >/dev/null || { echo "VD6SUB1-BLOCK tool=$cmd" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'VD6SUB1-BLOCK target=Linux-x86_64' >&2; exit 127;
}
test "$(fpc -iV)" = 3.2.2 || {
  echo 'VD6SUB1-BLOCK FPC!=3.2.2' >&2; exit 127;
}
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc)); then
    echo "VD6SUB1-FAIL rc=$rc" >&2
    for f in "$TMP"/O{1,2}/*.log "$TMP"/O{1,2}/*.err; do
      if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 25 "$f" >&2; fi
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
for opt in O1 O2; do
  mkdir -p "$TMP/$opt/units" "$TMP/$opt/bin" "$TMP/$opt/physical"
  if ! timeout 150s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh "-$opt" \
    -Fu"$ROOT/src" -FU"$TMP/$opt/units" -FE"$TMP/$opt/bin" \
    -otest-verifiedd6sub1 "$ROOT/scripts/test-verifiedd6sub1.pas" \
    >"$TMP/$opt/build.log" 2>"$TMP/$opt/build.err"; then
    cat "$TMP/$opt/build.log" "$TMP/$opt/build.err" >&2
    exit 1
  fi
  timeout 45s "$TMP/$opt/bin/test-verifiedd6sub1" \
    "$ROOT/external/sens" "$TMP/$opt/physical" \
    >"$TMP/$opt/test.log" 2>"$TMP/$opt/test.err" || {
      cat "$TMP/$opt/test.log" "$TMP/$opt/test.err" >&2
      exit 1
    }
  grep -Fq 'VERIFIED-D6SUB1-OK positives=8 negatives=12' "$TMP/$opt/test.log"
  for v in 1 2 3 7 15 127 1024 2047; do
    EXE="$TMP/$opt/physical/$v.elf"
    test -s "$EXE"
    readelf -h "$EXE" >"$TMP/$opt/elf.header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$opt/elf.header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$opt/elf.header"
    # Фактичний SUB у машинних інструкціях, не лише write literal.
    dd if="$EXE" of="$TMP/$opt/code.bin" bs=1 skip=120 status=none
    objdump -D -b binary -m i386:x86-64 --adjust-vma=0x78 \
      "$TMP/$opt/code.bin" >"$TMP/$opt/disasm"
    grep -Eiq 'sub.*%eax' "$TMP/$opt/disasm"
    chmod 500 "$EXE"
    timeout 8s "$EXE" >"$TMP/$opt/physical/$v.out.sens" \
      2>"$TMP/$opt/physical/$v.err"
    test ! -s "$TMP/$opt/physical/$v.err"
    cmp "$TMP/$opt/physical/$v.expected.sens" "$TMP/$opt/physical/$v.out.sens"
  done
done
for v in 1 2 3 7 15 127 1024 2047; do
  cmp "$TMP/O1/physical/$v.elf" "$TMP/O2/physical/$v.elf"
  cmp "$TMP/O1/physical/$v.out.sens" "$TMP/O2/physical/$v.out.sens"
done
echo 'VERIFIED-D6SUB1-CI-OK FPC=3.2.2 O1=pass O2=pass ELF=16 negatives=24 byte-identical=8 machine=executed oracle=NOT-RUN'
