#!/usr/bin/env bash
# G6.218 — фізичний D7 D3:101: успіх лише після повного машинного D1 sys_write.
# Це перевірка host Linux ABI; семантичний oracle не підмінюється.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЕЛФ-Д7-ЗАПИС-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp python3 readelf; do
  command -v "$tool" >/dev/null || {
    echo "ЕЛФ-Д7-ЗАПИС-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd7eq "$ROOT/scripts/test-elfd7eq.pas" \
  >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
timeout 30s "$TMP/bin/test-elfd7eq" "$ROOT/external/sens" "$TMP/свідки" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.err" >&2; exit 1;
  }
PASS=0
NEG=0
RECOVERY=0
for label in син-однакові син-різні; do
  ELF="$TMP/свідки/$label.elf"
  EXPECTED="$TMP/свідки/$label.expected.sens"
  test -s "$ELF" && test -s "$EXPECTED"
  chmod u+x "$ELF"
  readelf -h "$ELF" | grep -Eq 'Type:.*DYN'
  python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
code = Path(sys.argv[1]).read_bytes()[120:]
assert code[:2] == b'\x31\xc0', 'втрачено x86 accumulator'
assert code.count(b'\xb1') >= 7, 'немає 7 W7 XOR кроків'
assert b'\x84\xc0\x0f\x94\xc0' in code, 'відсутній TEST/SETE'
assert b'\x48\x83\xf8\x01\x75\x09' in code, 'відсутній CMP RAX,1 + JNE'
assert code.count(b'\x0f\x05') == 3, 'write + два host exit syscalls'
PY
  timeout 5s "$ELF" >"$TMP/$label.good.sens"
  cmp "$EXPECTED" "$TMP/$label.good.sens"
  test "$(wc -c < "$TMP/$label.good.sens")" -eq 1
  PASS=$((PASS+1))

  status=0
  if timeout 5s bash -c 'exec 1>&-; exec "$1"' bash "$ELF" \
      2>"$TMP/закрито.err"; then
    echo 'ЕЛФ-Д7-ЗАПИС-ПРОВАЛ: закритий fd1 прийнято' >&2; exit 1
  else status=$?; fi
  test "$status" -eq 2
  test ! -s "$TMP/закрито.err"
  NEG=$((NEG+1))

  status=0
  if timeout 5s "$ELF" >/dev/full 2>"$TMP/повний.err"; then
    echo 'ЕЛФ-Д7-ЗАПИС-ПРОВАЛ: ENOSPC прийнято' >&2; exit 1
  else status=$?; fi
  test "$status" -eq 2
  test ! -s "$TMP/повний.err"
  NEG=$((NEG+1))

  timeout 5s "$ELF" >"$TMP/$label.recovery.sens"
  cmp "$EXPECTED" "$TMP/$label.recovery.sens"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 2 && test "$NEG" -eq 4 && test "$RECOVERY" -eq 2
echo "ЕЛФ-Д7-ЗАПИС-ГАРАЗД FPC=checked ELF=2 D7-XOR=7 D1=T5M negatives=4 recovery=2 RAX=checked oracle=NOT-CHECKED joules=NOT-MEASURED"
