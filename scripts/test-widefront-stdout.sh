#!/usr/bin/env bash
# G6.128 — verified pinned WideIR → ELF64 stdout, без нового backend.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'ЕЛЬФ-ПОТІК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc git cmp grep readelf mktemp chmod wc head; do
  command -v "$tool" >/dev/null || {
    echo "ЕЛЬФ-ПОТІК-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "ЕЛЬФ-ПОТІК-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'src/senswidefrontstdout.lpr senswidefrontstdout' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'scripts/test-irwiderest.pas test-irwiderest'; do
  read -r source exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/fixtures.heap" timeout 30s \
  "$TMP/bin/test-irwiderest" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'G6.102-REST-FIXTURES-OK cases=28' "$TMP/fixtures.log"
MODE=--скомпілювати-фізичну-форму-в-потік
FILEMODE=--скомпілювати-фізичну-форму
PASS=0
while IFS=$'\t' read -r label dividend divisor expected; do
  test -n "$label"
  HEAPTRC="log=$TMP/stdout.heap" timeout 30s \
    "$TMP/bin/senswidefrontstdout" "$MODE" "$TMP/physical/$label.sens" \
    >"$TMP/$label.stdout.elf" 2>"$TMP/$label.err"
  test ! -s "$TMP/$label.err"
  test -s "$TMP/$label.stdout.elf"
  HEAPTRC="log=$TMP/baseline.heap" timeout 30s \
    "$TMP/bin/senswidefrontelf" "$FILEMODE" \
    "$TMP/physical/$label.sens" "$TMP/$label.file.elf" \
    >"$TMP/$label.baseline.log" 2>"$TMP/$label.baseline.err"
  test ! -s "$TMP/$label.baseline.err"
  cmp "$TMP/$label.file.elf" "$TMP/$label.stdout.elf"
  readelf -h "$TMP/$label.stdout.elf" >"$TMP/$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header.log"
  chmod 700 "$TMP/$label.stdout.elf"
  timeout 5s "$TMP/$label.stdout.elf" \
    >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  test "$(wc -c < "$TMP/$label.actual.sens")" -eq 3
  PASS=$((PASS+1))
done < "$TMP/physical/cases.tsv"
test "$PASS" -eq 28
# Ті самі фізичні байти → відтворюваний ELF, навіть у новому процесі.
HEAPTRC="log=$TMP/repeat.heap" timeout 30s \
  "$TMP/bin/senswidefrontstdout" "$MODE" "$TMP/physical/01.sens" \
  >"$TMP/repeat.elf" 2>"$TMP/repeat.err"
test ! -s "$TMP/repeat.err"
cmp "$TMP/repeat.elf" "$TMP/01.stdout.elf"
for log in fixtures stdout baseline repeat; do
  test -s "$TMP/$log.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$log.heap"
done

NEG=0
reject() {
  local label="$1"
  shift
  local rc=0
  HEAPTRC="log=$TMP/reject.heap" timeout 30s \
    "$TMP/bin/senswidefrontstdout" "$@" \
    >"$TMP/rejected.elf" 2>"$TMP/rejected.err" || rc=$?
  if [[ "$rc" -ne 2 || -s "$TMP/rejected.elf" ]] || \
     ! grep -Fq 'ЕЛЬФ-ПОТІК-ВІДМОВА:' "$TMP/rejected.err"; then
    echo "ЕЛЬФ-ПОТІК-НЕВІДМОВА: $label rc=$rc" >&2
    exit 1
  fi
  NEG=$((NEG+1))
}
for bad in other-d7 d1 d3-empty d7 d24 missing extra nested \
  two-roots dotted root-atom unclosed close-only bad-t5m empty \
  div-zero d24-right d48-left min-left min-right min-both \
  positive-negdiv-width; do
  reject "$bad" "$MODE" "$TMP/physical/$bad.sens"
done
reject 'проєкція-не-канон' "$MODE" "$TMP/physical/fake.lisp"
reject 'файл-відсутній' "$MODE" "$TMP/physical/not-existing.sens"
reject 'хибний-режим' --хибний "$TMP/physical/01.sens"
reject 'забагато-аргументів' "$MODE" "$TMP/physical/01.sens" зайве
reject 'немає-аргументів'
head -c 65537 /dev/zero > "$TMP/physical/too-large.sens"
reject 'завеликий' "$MODE" "$TMP/physical/too-large.sens"
test "$NEG" -eq 28
# Після пізньої помилки інший фізичний вираз усе ще компілюється.
HEAPTRC="log=$TMP/recovery.heap" timeout 30s \
  "$TMP/bin/senswidefrontstdout" "$MODE" "$TMP/physical/14.sens" \
  >"$TMP/recovery.elf" 2>"$TMP/recovery.err"
test ! -s "$TMP/recovery.err"
cmp "$TMP/recovery.elf" "$TMP/14.file.elf"
timeout 5s bash scripts/check-no-lcl.sh
echo "ЕЛЬФ-ПОТІК-ГОТОВО: фізичних=$PASS негативів=$NEG відновлення=так ELF64=байт-однаково pinned=$PIN енергія=НЕ-ВИМІРЮВАЛАСЯ"
