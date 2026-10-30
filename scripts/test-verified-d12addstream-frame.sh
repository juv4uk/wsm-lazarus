#!/usr/bin/env bash
# G6.231 — реальні фізичні D12 stdin-фрейми на Linux x86-64.
# Самодостатній перевірений механічний FPC свідок без Rust/Zig;
# окремий specialist workflow з pinned SENS oracle НЕ змінено.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-РІВНО-6-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in fpc timeout cmp readelf objdump head tail mktemp grep; do
  command -v "$cmd" >/dev/null || {
    echo "Д12-РІВНО-6-БЛОК: немає $cmd" >&2; exit 127;
  }
done
timeout 45s bash "$ROOT/scripts/check-pin.sh"
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 35 "$f" >&2; fi
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fpcunits" "$TMP/bin" "$TMP/frames"
for item in 'src/sensd12potikelf.lpr sensd12potikelf' 'scripts/test-elfd12potik.pas test-elfd12potik'; do
  read -r source exe <<<"$item"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$TMP/fpcunits" -FE"$TMP/bin" "-o$exe" "$ROOT/$source" >"$TMP/$exe.log" 2>&1
done
timeout 30s "$TMP/bin/test-elfd12potik" "$TMP/frames" >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'Д12-ПОТІК-СВІДКИ-ГОТОВО позитивів=13' "$TMP/fixtures.err"
ELF="$TMP/d12-addstream.elf"
timeout 15s "$TMP/bin/sensd12potikelf" --зібрати-D12-потік "$ELF" >"$TMP/compile.log" 2>"$TMP/compile.err"
test -x "$ELF" && test ! -s "$TMP/compile.err"
readelf -h "$ELF" >"$TMP/header.log"
grep -Eq 'Type:.*DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
tail -c +121 "$ELF" >"$TMP/code"
timeout 10s objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/disasm.log"
grep -Eiq 'cmp[[:space:]]+r10,0x6' "$TMP/disasm.log"
grep -Eiq 'add[[:space:]]+eax,r9d' "$TMP/disasm.log"
grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/disasm.log"
POS=0
while IFS="$(printf '\t')" read -r name left right; do
  test -n "$name"
  timeout 5s "$ELF" <"$TMP/frames/$name.frame" >"$TMP/actual.sens" 2>"$TMP/normal.err"
  test ! -s "$TMP/normal.err"
  cmp "$TMP/frames/$name-expected.sens" "$TMP/actual.sens"
  POS=$((POS+1))
done <"$TMP/cases.tsv"
test "$POS" -eq 13
{ head -c 2 "$TMP/frames/01.frame"; sleep 0.06;
  tail -c +3 "$TMP/frames/01.frame"; } |
  timeout 5s "$ELF" >"$TMP/fragmented.sens" 2>"$TMP/fragmented.err"
test ! -s "$TMP/fragmented.err"
cmp "$TMP/frames/01-expected.sens" "$TMP/fragmented.sens"
NEG=0
for name in overflow-up overflow-down empty short1 short5 extra invalid243 badlast; do
  RC=0
  timeout 5s "$ELF" <"$TMP/frames/$name.frame" >"$TMP/rejected.sens" 2>"$TMP/rejected.err" || RC=$?
  test "$RC" -eq 2 && test ! -s "$TMP/rejected.sens"
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/rejected.err"
  NEG=$((NEG+1))
done
for target in closed full; do
  RC=0
  if [[ "$target" == closed ]]; then
    timeout 5s "$ELF" <"$TMP/frames/01.frame" 1>&- 2>"$TMP/io.err" || RC=$?
  else
    timeout 5s "$ELF" <"$TMP/frames/01.frame" >/dev/full 2>"$TMP/io.err" || RC=$?
  fi
  test "$RC" -eq 2
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/io.err"
  NEG=$((NEG+1))
done
timeout 5s "$ELF" <"$TMP/frames/01.frame" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
cmp "$TMP/frames/01-expected.sens" "$TMP/recovery.sens"
test ! -s "$TMP/recovery.err"
test "$NEG" -eq 10
echo "VERIFIED-D12ADDSTREAM-FRAME-PASS physical=13 fragmented=2+4 negative=10 recovery=1 ELF64=ET_DYN machine=CPU-ADD-EINTR oracle=NOT-RUN energy=NOT-MEASURED"
