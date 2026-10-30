#!/usr/bin/env bash
# G6 / #47: жоден із байтів 243..255 не може опублікувати ELF зі stdin.
# Механічний тест реального FPC→T5M→WideIR→ELF64, НЕ SENS oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for cmd in timeout fpc git python3 mktemp cmp readelf grep chmod; do
  command -v "$cmd" >/dev/null || {
    echo "T5M-INVALID-BLOCK tool=$cmd" >&2
    exit 127
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'T5M-INVALID-BLOCK target=Linux-x86_64' >&2
  exit 127
}
test "$(fpc -iV)" = 3.2.2 || {
  echo 'T5M-INVALID-BLOCK fpc!=3.2.2' >&2
  exit 127
}
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  1f1bf676eeac605e065035d9dd2adaae807f1788
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "T5M-INVALID-FAIL status=$rc" >&2
    for log in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 30 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical" "$TMP/mut"
for pair in 'scripts/test-irwidefront.pas test-irwidefront' \
            'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source exe <<< "$pair"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2
      exit 1
    }
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'cases=16' "$TMP/generator.log"
test -s "$TMP/physical/09.sens"
test -s "$TMP/physical/09.expected.sens"
MODE=--скомпілювати-фізичний-потік

# Перший виконуваний ELF і вихідні фізичні байти — контроль наявної роботи.
timeout 30s "$TMP/bin/senswidepotikelf" "$MODE" \
  <"$TMP/physical/09.sens" >"$TMP/reference.elf" 2>"$TMP/reference.err"
test -s "$TMP/reference.elf"
readelf -h "$TMP/reference.elf" >"$TMP/reference.header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/reference.header"
chmod 700 "$TMP/reference.elf"
timeout 8s "$TMP/reference.elf" >"$TMP/reference.actual.sens" 2>"$TMP/reference-machine.err"
test ! -s "$TMP/reference-machine.err"
cmp "$TMP/physical/09.expected.sens" "$TMP/reference.actual.sens"

# Змінюємо тільки transport: кожен 0xF3..0xFF у трьох позиціях.
# Незмінна канонічна програма не перетворюється на український текст.
python3 - "$TMP/physical/09.sens" "$TMP/mut" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2])
assert source and all(value < 243 for value in source)
for value in range(243, 256):
    bad = bytes((value,))
    mid = len(source) // 2
    for position, content in (
        ("prefix", bad + source),
        ("inside", source[:mid] + bad + source[mid:]),
        ("suffix", source + bad),
    ):
        (out / (f"{value:03d}-{position}.sens")).write_bytes(content)
assert len(tuple(out.glob("*.sens"))) == 39
PY

NEG=0
for file in "$TMP"/mut/*.sens; do
  rc=0
  timeout 15s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$file" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  if [[ "$rc" -ne 2 || -s "$TMP/reject.out" || ! -s "$TMP/reject.err" ]]; then
    echo "T5M-INVALID-FAIL case=$(basename "$file") code=$rc stdout=$(wc -c <"$TMP/reject.out")" >&2
    cat "$TMP/reject.err" >&2
    exit 1
  fi
  # ASCII діагностика фізичного формату, незалежна від host-кодової сторінки.
  grep -Fq 'T5M' "$TMP/reject.err" || {
    echo "T5M-INVALID-FAIL missing-diagnostic $(basename "$file")" >&2
    cat "$TMP/reject.err" >&2
    exit 1
  }
  NEG=$((NEG+1))
done
test "$NEG" -eq 39

# Після кожної відмови відновлюваність доводимо повторною компіляцією
# того самого canonical фізичного джерела та byte-identical ELF.
timeout 30s "$TMP/bin/senswidepotikelf" "$MODE" \
  <"$TMP/physical/09.sens" >"$TMP/recovered.elf" 2>"$TMP/recovered.err"
cmp "$TMP/reference.elf" "$TMP/recovered.elf"
chmod 700 "$TMP/recovered.elf"
timeout 8s "$TMP/recovered.elf" >"$TMP/recovered.actual.sens" 2>"$TMP/recovered-machine.err"
test ! -s "$TMP/recovered-machine.err"
cmp "$TMP/physical/09.expected.sens" "$TMP/recovered.actual.sens"
echo 'T5M-INVALID-OK forbidden_values=13 positions=3 rejects=39 stdout=zero recovery=identical-ELF machine=executed oracle=NOT-CHECKED energy=NOT-MEASURED'
