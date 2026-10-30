#!/usr/bin/env bash
# G6.238 — справжній Linux D5 SUB ELF64: короткий stdin не є помилкою.
# Один pinned D5 .sens якір компілюється через існуючі FPC механізми.
# Два D12 T5M атоми у stdin — host transport, не .sens програма.
# Семантичні порівняння з SENS належать specialist suite; oracle=NOT-RUN.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-SUB-КАДР-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump head tail mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "Д5-SUB-КАДР-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 45s bash scripts/check-pin.sh
TMP=$(mktemp -d)
finish() {
  local rc=$?
  if ((rc != 0)); then
    echo "Д5-SUB-КАДР-ПРОВАЛ rc=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 20 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'src/sensd12subpotikelf.lpr sensd12subpotikelf' \
  'scripts/test-elfd12subpotik.pas test-elfd12subpotik'; do
  read -r source program <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$program" \
    "$ROOT/$source" >"$TMP/$program.log" 2>&1 || {
      cat "$TMP/$program.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$program"
done
timeout 30s "$TMP/bin/test-elfd12subpotik" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'Д5-SUB-ПОТІК-СВІДКИ-ГОТОВО' "$TMP/fixtures.log"

ELF="$TMP/sub-stream.elf"
timeout 40s "$TMP/bin/sensd12subpotikelf" \
  --зібрати-D5-віднімання-потік "$TMP/physical/03.sens" "$ELF" \
  >"$TMP/compile.log" 2>"$TMP/compile.err"
test -x "$ELF" && test ! -s "$TMP/compile.err"
readelf -h "$ELF" >"$TMP/header.log"
grep -Eq 'Type:.*DYN' "$TMP/header.log"
tail -c +121 "$ELF" >"$TMP/code.bin"
timeout 15s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/code.bin" >"$TMP/disasm.log"
grep -Eiq 'sub[[:space:]]+eax,r9d' "$TMP/disasm.log"
grep -Eiq 'cmp[[:space:]]+r10,0x6' "$TMP/disasm.log"
grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/disasm.log"

PASS=0
for name in 01 03 04 06 11 12 16; do
  timeout 5s "$ELF" <"$TMP/physical/$name.frame" \
    >"$TMP/$name.actual.sens" 2>"$TMP/$name.err"
  test ! -s "$TMP/$name.err"
  cmp "$TMP/physical/$name.expected.sens" "$TMP/$name.actual.sens"
  PASS=$((PASS+1))
done
test "$PASS" -eq 7

# Два розбиття одного канонічного шестибайтового кадру:
# справжній POSIX pipe, незалежні write перед EOF.
{ head -c 2 "$TMP/physical/03.frame"; sleep 0.06;
  tail -c +3 "$TMP/physical/03.frame"; } |
  timeout 5s "$ELF" >"$TMP/frag2.sens" 2>"$TMP/frag2.err"
cmp "$TMP/physical/03.expected.sens" "$TMP/frag2.sens"
test ! -s "$TMP/frag2.err"
{ head -c 1 "$TMP/physical/03.frame"; sleep 0.06;
  tail -c +2 "$TMP/physical/03.frame"; } |
  timeout 5s "$ELF" >"$TMP/frag1.sens" 2>"$TMP/frag1.err"
cmp "$TMP/physical/03.expected.sens" "$TMP/frag1.sens"
test ! -s "$TMP/frag1.err"

NEG=0
for name in empty short1 short5 extra newline invalid243 badfirst; do
  rc=0
  timeout 5s "$ELF" <"$TMP/physical/$name.frame" \
    >"$TMP/rejected.sens" 2>"$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/rejected.sens"
  grep -Fq 'ВІДМОВА' "$TMP/rejected.err"
  NEG=$((NEG+1))
done
for where in closed full; do
  rc=0
  if [[ "$where" == closed ]]; then
    timeout 5s "$ELF" <"$TMP/physical/03.frame" 1>&- \
      2>"$TMP/io.err" || rc=$?
  else
    timeout 5s "$ELF" <"$TMP/physical/03.frame" \
      >/dev/full 2>"$TMP/io.err" || rc=$?
  fi
  test "$rc" -eq 2
  grep -Fq 'ВІДМОВА' "$TMP/io.err"
  NEG=$((NEG+1))
done
timeout 5s "$ELF" <"$TMP/physical/03.frame" \
  >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
test ! -s "$TMP/recovered.err"
cmp "$TMP/physical/03.expected.sens" "$TMP/recovered.sens"
test "$NEG" -eq 9
echo "VERIFIED-D12SUBSTREAM-FRAME-PASS physical=$PASS fragmented=2+4,1+5 negative=$NEG recovery=1 machine=SUB ELF64=ET_DYN oracle=NOT-RUN energy=NOT-MEASURED"
