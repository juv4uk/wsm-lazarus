#!/usr/bin/env bash
# G6 — WideIR → ELF64: повний host stdout після допустимого short write.
# Цей тест НЕ встановлює семантику SENS; наявні байти verified ELF
# звіряються з файловим CLI і реальними машинними результатами.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ШИРОКИЙ-WRITE-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for tool in fpc timeout readelf cmp grep git mktemp tail chmod; do
  command -v "$tool" >/dev/null || {
    echo "ШИРОКИЙ-WRITE-БЛОК: бракує $tool" >&2;exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh
TMP=$(mktemp -d)
on_exit() {
  local rc=$?
  if ((rc != 0)); then
    echo "ШИРОКИЙ-WRITE-ЗБІЙ код=$rc" >&2
    for log in "$TMP"/*.build "$TMP"/*.err "$TMP"/fixtures.out; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2;tail -n 30 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap on_exit EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      tail -n 70 "$TMP/$name.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
# Порівняння двох CLI підтверджує byte-exact ELF, а machine
# execution — відповідь фізичного T5M; це не незалежний SENS oracle.
POSITIVES=0
for label in 01 09 15 16; do
  source="$TMP/physical/$label.sens"
  test -s "$source"
  timeout 25s "$TMP/bin/senswidefrontelf" \
    --скомпілювати-фізичну-форму "$source" "$TMP/$label.file.elf" \
    >"$TMP/$label.file.out" 2>"$TMP/$label.file.err"
  timeout 25s "$TMP/bin/senswidepotikelf" \
    --скомпілювати-фізичний-потік \
    <"$source" >"$TMP/$label.stream.elf" 2>"$TMP/$label.stream.err"
  cmp "$TMP/$label.file.elf" "$TMP/$label.stream.elf"
  test ! -s "$TMP/$label.stream.err" || \
    grep -Fq '0 unfreed memory blocks' "$TMP/$label.stream.err"
  timeout 5s readelf -h "$TMP/$label.stream.elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  chmod 700 "$TMP/$label.stream.elf"
  timeout 5s "$TMP/$label.stream.elf" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  test ! -s "$TMP/$label.machine.err"
  POSITIVES=$((POSITIVES+1))
done

# Перед verified-admission: зіпсований T5M мусить відмовитися
# БЕЗ байтів ELF у stdout, навіть якщо перед цим був success.
rc=0
timeout 25s "$TMP/bin/senswidepotikelf" \
  --скомпілювати-фізичний-потік \
  <"$TMP/physical/bad-t5m.sens" \
  >"$TMP/bad.out" 2>"$TMP/bad.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/bad.out"
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/bad.err"

# Після успішної компіляції fd1/ENOSPC не можна називати exit(0).
# Обрано фізичну програму, що уже мала machine PASS вище.
CLOSED=0
rc=0
timeout 25s bash -c 'exec 1>&-; exec "$1" "$2" <"$3"' _ \
  "$TMP/bin/senswidepotikelf" --скомпілювати-фізичний-потік \
  "$TMP/physical/09.sens" 2>"$TMP/closed.err" || rc=$?
test "$rc" -eq 2
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/closed.err"
CLOSED=$((CLOSED+1))

FULL=0
rc=0
timeout 25s "$TMP/bin/senswidepotikelf" \
  --скомпілювати-фізичний-потік \
  <"$TMP/physical/09.sens" >/dev/full 2>"$TMP/full.err" || rc=$?
test "$rc" -eq 2
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/full.err"
FULL=$((FULL+1))

timeout 25s "$TMP/bin/senswidepotikelf" \
  --скомпілювати-фізичний-потік \
  <"$TMP/physical/09.sens" \
  >"$TMP/recovered.elf" 2>"$TMP/recovered.err"
cmp "$TMP/09.file.elf" "$TMP/recovered.elf"
test "$POSITIVES" -eq 4 && test "$CLOSED" -eq 1 && test "$FULL" -eq 1
echo 'WIDE-PIPE-WRITE-PASS fpc=checked elf=4 t5m=4 malformed=1 closed=1 full=1 recovery=1 short-write-loop=CODE-GUARD independent-oracle=NOT-RUN energy=NOT-MEASURED'
