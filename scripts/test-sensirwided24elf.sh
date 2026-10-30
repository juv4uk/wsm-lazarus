#!/usr/bin/env bash
# G6.261 — справжній CLI: фізичний D5/W24 source → pinned WideIR → ELF64.
# Використовує тільки існуючі бібліотечні модулі FPC і тестові .sens.
# Не компілює Rust/інші важкі мови й не додає новий CI workflow.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D24-КОМАНДА-БЛОК: потрібна Linux x86-64 система' >&2; exit 127;
}
for bin in timeout fpc git cmp mktemp readelf objdump chmod stat wc head grep ln; do
  command -v "$bin" >/dev/null || {
    echo "D24-КОМАНДА-БЛОК: бракує $bin" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
[[ "$(git -C external/sens rev-parse HEAD)" == "$PIN" ]]
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log "$TMP"/*.err; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 45 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/repeat"
FPC_BIN="${FPC:-fpc}"
# Збираємо САМЕ новий compiler executable та попередній physical fixture
# generator із перевірками меж FPC, а не інтерпретуємо статус готовності.
for spec in "src/sensirwided24elf.lpr:sensirwided24elf" \
            "scripts/test-irwided24carry.pas:test-irwided24carry"; do
  IFS=: read -r src exe <<< "$spec"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$src" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;
    }
done
test -x "$TMP/bin/sensirwided24elf"
HEAPTRC="log=$TMP/fixture.heap" timeout 90s \
  "$TMP/bin/test-irwided24carry" "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err" || {
    cat "$TMP/fixture.log" "$TMP/fixture.err" >&2; exit 1;
  }
grep -Fq 'IR-D24-CARRY-OK positives=10 negative=12 recovery=1' "$TMP/fixture.log"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
test ! -s "$TMP/fixture.err"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 10
MODE=--скомпілювати-D24-форму
PASS=0
while IFS=$'\t' read -r label left right expected; do
  [[ "$label" =~ ^[0-9][0-9]$ ]] || exit 1
  source="$TMP/physical/$label.program.sens"
  expected_bin="$TMP/physical/$label.elf"
  expected_out="$TMP/physical/$label.expected.sens"
  output="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 30s \
    "$TMP/bin/sensirwided24elf" "$MODE" "$source" "$output" \
    >"$TMP/$label.log" 2>"$TMP/$label.err"
  grep -Fq 'КОМПІЛЯТОР-D24-ГОТОВО: source=physical-D5-W24 IR=pinned-wide machine=ADD-ADC ELF64=PIE bytes=' "$TMP/$label.log"
  test ! -s "$TMP/$label.err"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  test -x "$output" && test "$(stat -c %a "$output")" -eq 700
  # ВАЖЛИВО: source-backed CLI породив той самий ELF, що й внутрішній
  # verified WideIR lowering; жодних прихованих перепаковок чи host fold.
  cmp "$expected_bin" "$output"
  timeout 5s readelf -h "$output" >"$TMP/elf.header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header.log"
  timeout 5s "$output" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  test "$(wc -c < "$TMP/$label.actual.sens")" -eq 5
  cmp "$expected_out" "$TMP/$label.actual.sens"
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 10
# Повтор AOT не повинен змінити жоден машинний байт.
timeout 30s "$TMP/bin/sensirwided24elf" "$MODE" \
  "$TMP/physical/01.program.sens" "$TMP/repeat/01.elf" >"$TMP/repeat.log"
cmp "$TMP/01.elf" "$TMP/repeat/01.elf"
# Перевіряємо реальний ADD→ADC в ELF машині, не тільки фізичний stdout.
tail -c +121 "$TMP/01.elf" >"$TMP/body.bin"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/body.bin" >"$TMP/body.dis"
grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/body.dis"
grep -Eq 'adc[[:space:]]+edx,ebx' "$TMP/body.dis"

NEG=0
reject() {
  local label="$1"; shift
  local dest="$TMP/negative-$NEG.elf"
  local rc=0
  HEAPTRC="log=$TMP/reject-$NEG.heap" timeout 30s \
    "$TMP/bin/sensirwided24elf" "$@" "$dest" \
    >"$TMP/reject-$NEG.log" 2>"$TMP/reject-$NEG.err" || rc=$?
  if [[ "$rc" != 2 || -e "$dest" || -L "$dest" || -s "$TMP/reject-$NEG.log" ]] ||
     ! grep -Fq 'КОМПІЛЯТОР-D24-ВІДМОВА:' "$TMP/reject-$NEG.err"; then
    echo "D24-КОМАНДА-ПОМИЛКА: негатив $label rc=$rc" >&2
    cat "$TMP/reject-$NEG.log" "$TMP/reject-$NEG.err" >&2
    exit 1
  fi
  NEG=$((NEG+1))
}
: > "$TMP/empty.sens"
printf '\377' > "$TMP/corrupt.sens"
head -c 11 "$TMP/physical/01.program.sens" >"$TMP/truncated.sens"
head -c 65537 /dev/zero >"$TMP/large.sens"
cp "$TMP/physical/01.program.sens" "$TMP/surrogate.lisp"
reject empty "$MODE" "$TMP/empty.sens"
reject corrupt "$MODE" "$TMP/corrupt.sens"
reject truncated "$MODE" "$TMP/truncated.sens"
reject large "$MODE" "$TMP/large.sens"
reject wrong-source-extension "$MODE" "$TMP/surrogate.lisp"
reject missing-source "$MODE" "$TMP/missing.sens"
reject wrong-mode --вигаданий-D24 "$TMP/physical/01.program.sens"
reject missing-mode "$TMP/physical/01.program.sens"
test "$NEG" -eq 8

# Для зайнятої цілі і симлінка не повинно бути перезапису або нового
# ELF; GitHub verifier ще раз виконуватиме вже створений коректний ELF.
before="$TMP/01.elf"
out="$TMP/occupied.elf"
cp "$before" "$out"
rc=0
timeout 30s "$TMP/bin/sensirwided24elf" "$MODE" \
  "$TMP/physical/02.program.sens" "$out" \
  >"$TMP/occupied.log" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.log"
cmp "$before" "$out"
grep -Fq 'КОМПІЛЯТОР-D24-ВІДМОВА:' "$TMP/occupied.err"
ln -s "$before" "$TMP/linked.elf"
rc=0
timeout 30s "$TMP/bin/sensirwided24elf" "$MODE" \
  "$TMP/physical/02.program.sens" "$TMP/linked.elf" \
  >"$TMP/linked.log" 2>"$TMP/linked.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/linked.log" && test -L "$TMP/linked.elf"
cmp "$before" "$TMP/linked.elf"
grep -Fq 'КОМПІЛЯТОР-D24-ВІДМОВА:' "$TMP/linked.err"

# Відновлення після негативів: новий результат виконується.
timeout 30s "$TMP/bin/sensirwided24elf" "$MODE" \
  "$TMP/physical/02.program.sens" "$TMP/repeat/recovered.elf" \
  >"$TMP/recovered.log" 2>"$TMP/recovered.err"
test ! -s "$TMP/recovered.err"
test "$(stat -c %a "$TMP/repeat/recovered.elf")" -eq 700
timeout 5s "$TMP/repeat/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/02.expected.sens" "$TMP/recovered.sens"
echo "D24-КОМАНДА-ГОТОВО FPC=checked physical-source=$PASS ELF64=$PASS negative=$NEG no-clobber=2 recovery=1 deterministic=1 T5M=exact oracle=NOT-RUN energy=NOT-MEASURED"
