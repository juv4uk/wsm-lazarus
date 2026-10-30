#!/usr/bin/env bash
# G6 — новий фізичний stdin→ELF64 stdout поверх того самого pinned WideIR.
# Немає нового compiler backend чи перетворення української проєкції на канон.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout cmp readelf python3 grep mktemp git; do
  command -v "$tool" >/dev/null || { echo "WIDEIR-ПОТІК: немає $tool" >&2; exit 127; }
done
./scripts/check-pin.sh
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
TMP=$(mktemp -d)
failure() {
  local rc=$?
  echo "WIDEIR-ПОТІК-ТЕСТ-ПОМИЛКА: рядок=$1 статус=$rc" >&2
  for log in "$TMP"/*.err "$TMP"/build-*.log; do
    if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 10 "$log" >&2; fi
  done
  exit "$rc"
}
trap 'failure "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for row in   'src/senswidefrontpotik.lpr senswidefrontpotik'   'src/senswidefrontelf.lpr senswidefrontelf'   'scripts/test-irwidefront.pas test-irwidefront'; do
  read -r source bin <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh     -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin"     "$ROOT/$source" >"$TMP/build-$bin.log" 2>&1 || {
      cat "$TMP/build-$bin.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$bin"
done
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1" || {
      cat "$1" >&2; exit 1;
    }
  fi
}
timeout 35s "$TMP/bin/test-irwidefront" "$TMP/physical"   >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
check_heap "$TMP/generator.err"
PASS=0
ORACLE_PASS=0
ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" =     2c498b35af53c085450eac6f51b87facf7f9aa47
fi
while IFS=$'\t' read -r label kind a b expected width; do
  test -n "$label"
  timeout 30s "$TMP/bin/senswidefrontpotik" --скомпілювати-потік     <"$TMP/physical/$label.sens" >"$TMP/$label.stream.elf" 2>"$TMP/$label.stream.err"
  check_heap "$TMP/$label.stream.err"
  test -s "$TMP/$label.stream.elf"
  timeout 30s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму     "$TMP/physical/$label.sens" "$TMP/$label.file.elf"     >"$TMP/$label.file.out" 2>"$TMP/$label.file.err"
  check_heap "$TMP/$label.file.err"
  cmp "$TMP/$label.file.elf" "$TMP/$label.stream.elf"
  readelf -h "$TMP/$label.stream.elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  chmod 700 "$TMP/$label.stream.elf"
  timeout 10s "$TMP/$label.stream.elf" >"$TMP/$label.actual.sens"     2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  if [[ -n "$ORACLE" ]]; then
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/$label.lisp" ;;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/$label.lisp" ;;
      *) echo "невідомий тестовий індекс $kind" >&2; exit 2 ;;
    esac
    timeout 60s "$ORACLE" "$TMP/$label.lisp"       >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 16; fi

# Фрагментований pipe не потребує host-заголовка або текстового reader.
python3 - "$TMP/physical/15.sens" "$TMP/bin/senswidefrontpotik"   "$TMP/15.stream.elf" <<'PY'
import pathlib, subprocess, sys
payload = pathlib.Path(sys.argv[1]).read_bytes()
expected = pathlib.Path(sys.argv[3]).read_bytes()
p = subprocess.Popen([sys.argv[2], '--скомпілювати-потік'],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE)
for byte in payload:
    p.stdin.write(bytes([byte]))
    p.stdin.flush()
p.stdin.close()
actual = p.stdout.read()
err = p.stderr.read()
rc = p.wait(timeout=15)
assert rc == 0 and actual == expected, (rc, len(actual), len(expected), err)
assert b'unfreed memory blocks' not in err or b'0 unfreed memory blocks' in err, err
PY

python3 - "$TMP/overlimit.sens" "$TMP/late-corrupt.sens"   "$TMP/physical/15.sens" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b'\xff' * 65537)
Path(sys.argv[2]).write_bytes(Path(sys.argv[3]).read_bytes() + b'\xff')
PY
NEG=0
reject() {
  local input="$1" rc=0
  timeout 25s "$TMP/bin/senswidefrontpotik" --скомпілювати-потік     <"$input" >"$TMP/negative.stdout" 2>"$TMP/negative.stderr" || rc=$?
  if [[ "$rc" -ne 2 ]] || [[ -s "$TMP/negative.stdout" ]]; then
    echo "WIDEIR-ПОТІК: очікувана атомарна відмова, код=$rc, вхід=$input" >&2
    cat "$TMP/negative.stderr" >&2
    exit 1
  fi
  grep -Fq 'WIDEIR-ПОТІК-ВІДМОВА:' "$TMP/negative.stderr"
  check_heap "$TMP/negative.stderr"
  NEG=$((NEG+1))
}
for invalid in other-d5 other-d6 other-d7 bad-zero-arity bad-zero-empty   bad-zero-d1 bad-zero-d7 bad-less-arity bad-less-d24 bad-less-d1   bad-greater-arity bad-greater-nested bad-abs-arity bad-abs-d24 bad-abs-d3   two-roots dotted unclosed root-atom bad-t5m empty; do
  reject "$TMP/physical/$invalid.sens"
done
reject "$TMP/overlimit.sens"
reject "$TMP/late-corrupt.sens"
test "$NEG" -eq 23
rc=0
timeout 10s "$TMP/bin/senswidefrontpotik" --невідомо   <"$TMP/physical/01.sens" >"$TMP/wrong.out" 2>"$TMP/wrong.err" || rc=$?
test "$rc" -eq 64 && test ! -s "$TMP/wrong.out"
grep -Fq 'Використання:' "$TMP/wrong.err"
timeout 20s "$TMP/bin/senswidefrontpotik" --скомпілювати-потік   <"$TMP/physical/15.sens" >"$TMP/recovered.elf" 2>"$TMP/recovered.err"
cmp "$TMP/15.stream.elf" "$TMP/recovered.elf"
check_heap "$TMP/recovered.err"
echo "WIDEIR-ПОТІК-ГАРАЗД: FPC=так фізичні=$PASS ELF-побайтово=$PASS машина=$PASS негативи=$NEG fragmented=так oracle=$ORACLE_PASS/16-with-pinned-option joules=НЕ-ВИМІРЯНО"
