#!/usr/bin/env bash
# G6.240 — лише реальний Linux x86-64 FPC + pinned фізичний D12/D24.
# Нових CI/workflow немає: штатний test-verified-all.sh запускає цей файл.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'АДАПТИВНЕ-КАДР-БЛОК: Linux x86-64 потрібен' >&2;exit 127;
}
for tool in fpc timeout cmp readelf grep mktemp head tail python3; do
  command -v "$tool" >/dev/null || {
    echo "АДАПТИВНЕ-КАДР-БЛОК: немає $tool" >&2;exit 127;
  }
done
timeout 80s bash ./scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc!=0)); then for f in "$TMP"/*.build "$TMP"/*.err; do
  if [[ -s "$f" ]]; then echo "--- $f" >&2;tail -n 50 "$f" >&2;fi
done;fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units-cli" "$TMP/units-test" "$TMP/bin" "$TMP/data"
for row in \
  'scripts/test-adaptive-frame.pas test-adaptive-frame units-test' \
  'src/sensd12addpotikadaptive.lpr sensd12addpotikadaptive units-cli'; do
  read -r src exe units <<<"$row"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
      -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$exe" "$ROOT/$src" \
      >"$TMP/$exe.build" 2>&1; then
    cat "$TMP/$exe.build" >&2;exit 1
  fi
done
timeout 45s "$TMP/bin/test-adaptive-frame" "$TMP/data" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fq 'АДАПТИВНЕ-КАДР-СВІДКИ-ГОТОВО profiles=2 cases=4 donor=raw framed=once double=reject' "$TMP/fixture.log"
POS=0;FRAGMENT=0;NEG=0;RECOVERY=0
for op in add sub; do
  if [[ "$op" == add ]]; then
    mode=--зібрати-адаптивне-D5-додавання
    machine=$'\x44\x89\xc0\x44\x01\xc8\x89\xc3'
  else
    mode=--зібрати-адаптивне-D5-віднімання
    machine=$'\x44\x89\xc0\x44\x29\xc8\x89\xc3'
  fi
  elf="$TMP/$op.elf"
  timeout 35s "$TMP/bin/sensd12addpotikadaptive" "$mode" \
    "$TMP/data/$op.anchor.sens" "$elf" >"$TMP/$op.compile" 2>"$TMP/$op.err"
  test -x "$elf" && test ! -s "$TMP/$op.err"
  timeout 8s readelf -h "$elf" >"$TMP/$op.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$op.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$op.header"
  python3 - "$elf" "$op" <<'PY'
from pathlib import Path
import sys,struct
data=Path(sys.argv[1]).read_bytes()
mode=sys.argv[2]
assert struct.unpack_from('<Q',data,96)[0]==len(data)
assert struct.unpack_from('<Q',data,104)[0]==len(data)
assert data[120:127]==bytes.fromhex('48 83 ec 20 45 31 d2')
assert bytes.fromhex('49 83 fa 06') in data
assert bytes.fromhex('48 83 f8 fc') in data
alu=bytes.fromhex('44 89 c0 44 01 c8 89 c3' if mode=='add'
                  else '44 89 c0 44 29 c8 89 c3')
assert alu in data, 'немає реального native ADD/SUB'
assert bytes.fromhex('48 83 f8 05 0f 85') in data
print('АДАПТИВНЕ-КАДР-ISA-ГОТОВО',mode, 'frame=6+EOF ALU=CPU')
PY
  for width in small wide; do
    label="$op-$width"
    frame="$TMP/data/$label.frame"
    expected="$TMP/data/$label.expected.sens"
    timeout 8s "$elf" <"$frame" >"$TMP/$label.actual.sens" 2>"$TMP/$label.err"
    test ! -s "$TMP/$label.err"
    cmp "$expected" "$TMP/$label.actual.sens"
    if [[ "$width" == small ]]; then
      test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3
    else
      test "$(wc -c <"$TMP/$label.actual.sens")" -eq 5
    fi
    POS=$((POS+1))
    { head -c 2 "$frame";sleep 0.07;tail -c +3 "$frame"; } |
      timeout 8s "$elf" >"$TMP/$label.fragmented.sens" 2>"$TMP/$label.fragmented.err"
    test ! -s "$TMP/$label.fragmented.err"
    cmp "$expected" "$TMP/$label.fragmented.sens"
    FRAGMENT=$((FRAGMENT+1))
  done
  frame="$TMP/data/$op-small.frame"
  : >"$TMP/empty"
  head -c 5 "$frame" >"$TMP/short"
  { cat "$frame";printf '\0'; } >"$TMP/extra"
  { printf '\377';tail -c +2 "$frame"; } >"$TMP/invalid"
  for malformed in empty short extra invalid; do
    rc=0
    timeout 8s "$elf" <"$TMP/$malformed" >"$TMP/bad.out" 2>"$TMP/bad.err" || rc=$?
    test "$rc" -eq 2 && test ! -s "$TMP/bad.out"
    grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/bad.err"
    NEG=$((NEG+1))
  done
  rc=0
  timeout 8s "$elf" <"$frame" 1>&- 2>"$TMP/bad.err" || rc=$?
  test "$rc" -eq 2
  NEG=$((NEG+1))
  rc=0
  timeout 8s "$elf" <"$frame" >/dev/full 2>"$TMP/bad.err" || rc=$?
  test "$rc" -eq 2
  NEG=$((NEG+1))
  timeout 8s "$elf" <"$frame" >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
  test ! -s "$TMP/recovered.err"
  cmp "$TMP/data/$op-small.expected.sens" "$TMP/recovered.sens"
  RECOVERY=$((RECOVERY+1))
done
test "$POS" -eq 4 && test "$FRAGMENT" -eq 4
test "$NEG" -eq 12 && test "$RECOVERY" -eq 2
echo "VERIFIED-ADAPTIVE-FRAME-PASS FPC=checked physical=4 fragmented=4 negative=12 recovery=2 donor=unwrapped double=reject ISA=ADD/SUB/D12/D24 oracle=NOT-RUN energy=NOT-MEASURED"
