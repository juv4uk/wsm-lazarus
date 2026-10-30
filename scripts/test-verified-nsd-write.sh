#!/usr/bin/env bash
# G6.219 — перевірка машинного Linux write для фізичного D6 НСД → D12 T5M.
# ВИКОНУЄТЬСЯ через наявний test-verified-all.sh, без нового workflow/оракула.
set -Eeuo pipefail
trap 'echo "НСД-WRITE-ЗБІЙ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'НСД-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump awk grep mktemp tail head; do
  command -v "$tool" >/dev/null || {
    echo "НСД-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
grep -Fq '(010101 (ук нсд) (укр найбільший-спільний-дільник)' \
  external/sens/lib/domains/d6.lisp

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixtures" "$TMP/свідки"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-cli" -FE"$TMP/bin" \
  -osensd12nsdelf "$ROOT/src/sensd12nsdelf.lpr" >"$TMP/cli-build.log" 2>&1 || {
    tail -40 "$TMP/cli-build.log" >&2; exit 1;
  }
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-fixtures" -FE"$TMP/bin" \
  -otest-elfd12nsd-fixtures "$ROOT/scripts/test-elfd12nsd-fixtures.pas" \
  >"$TMP/fixtures-build.log" 2>&1 || {
    tail -40 "$TMP/fixtures-build.log" >&2; exit 1;
  }
timeout 30s "$TMP/bin/test-elfd12nsd-fixtures" "$TMP/свідки" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'cases=8' "$TMP/fixtures.out"
grep -Fq 'negatives=8' "$TMP/fixtures.out"

GOOD=0
BAD=0
RECOVERY=0
for label in 01 03 04 08; do
  ELF="$TMP/$label.elf"
  timeout 10s "$TMP/bin/sensd12nsdelf" --нсд-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" "$ELF" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  grep -Fq 'machine-euclid-div=1' "$TMP/compiler.out"
  test ! -s "$TMP/compiler.err" && test -x "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"
  tail -c +121 "$ELF" | head -c -36 >"$TMP/elf.code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/elf.code" >"$TMP/elf.dis"
  grep -Eiq 'div[[:space:]]+ecx' "$TMP/elf.dis"
  grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/elf.dis"
  grep -Eiq 'setne[[:space:]]+dil' "$TMP/elf.dis"
  grep -Eiq 'shl[[:space:]]+edi,1' "$TMP/elf.dis"
  awk '/[[:space:]]syscall/{n++} END{exit(n==2 ? 0 : 1)}' "$TMP/elf.dis"

  timeout 5s "$ELF" >"$TMP/result.sens" 2>"$TMP/run.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/result.sens"
  test ! -s "$TMP/run.err"
  test "$(wc -c < "$TMP/result.sens")" -eq 3
  GOOD=$((GOOD+1))

  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/run.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/run.err"
  BAD=$((BAD+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/run.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/run.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/run.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/recovered.sens"
  test ! -s "$TMP/run.err"
  RECOVERY=$((RECOVERY+1))
done

test "$GOOD" -eq 4 && test "$BAD" -eq 8 && test "$RECOVERY" -eq 4
echo "НСД-WRITE-PASS positives=$GOOD negatives=$BAD recovery=$RECOVERY physical=D12-T5M machine=DIV/CMP/SETNE syscalls=2 oracle=NOT-RUN energy=NOT-MEASURED"
