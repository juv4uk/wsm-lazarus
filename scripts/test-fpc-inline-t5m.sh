#!/usr/bin/env bash
# G6: host assembler x86-64 лише як механічна можливість майбутнього backend.
# Не робить із T5M число/рядок, не створює нового reader/dispatch чи ISA.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'АСЕМБЛЕР-T5M-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for exe in fpc git timeout mktemp grep cmp objdump; do
  command -v "$exe" >/dev/null || {
    echo "АСЕМБЛЕР-T5M-БЛОК: немає $exe" >&2
    exit 127
  }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"

TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc)); then
    echo "АСЕМБЛЕР-T5M-ПРОВАЛ exit=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 28 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

for opt in 1 2; do
  mkdir -p "$TMP/o$opt/units" "$TMP/o$opt/bin"
  timeout 180s fpc -B -Mobjfpc "-O$opt" -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/o$opt/units" -FE"$TMP/o$opt/bin" \
    -otest-fpc-inline-t5m "$ROOT/scripts/test-fpc-inline-t5m.pas" \
    >"$TMP/o$opt-build.log" 2>"$TMP/o$opt-build.err" || {
      cat "$TMP/o$opt-build.log" "$TMP/o$opt-build.err" >&2
      exit 1
    }
  test -x "$TMP/o$opt/bin/test-fpc-inline-t5m"
  timeout 30s "$TMP/o$opt/bin/test-fpc-inline-t5m" \
    >"$TMP/o$opt-result.log" 2>"$TMP/o$opt-result.err"
  grep -Eq '^INLINE-T5M-PASS vectors=1024 double=1024 physical_bytes=[1-9][0-9]* blocks=[1-9][0-9]* words=64 negative=1 reference=Pascal checks=[1-9][0-9]* oracle=NOT_RUN energy=NOT_MEASURED$' "$TMP/o$opt-result.log"
  test "$(wc -l <"$TMP/o$opt-result.log")" -eq 1
  if grep -Fq 'unfreed memory blocks' "$TMP/o$opt-result.err"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/o$opt-result.err"
  else
    test ! -s "$TMP/o$opt-result.err"
  fi
  timeout 10s objdump -d "$TMP/o$opt/bin/test-fpc-inline-t5m" \
    >"$TMP/o$opt-disasm.log"
  grep -Eq 'bswap[[:space:]]+%?rax' "$TMP/o$opt-disasm.log" || {
    echo 'АСЕМБЛЕР-T5M-ПРОВАЛ: немає справжньої інструкції BSWAP RAX' >&2
    exit 1
  }
done
cmp "$TMP/o1-result.log" "$TMP/o2-result.log"
echo 'INLINE-T5M-MACHINE-PASS FPC=checked O1=1 O2=1 asm=BSWAP-RAX canonical=T5M reference=Pascal oracle=NOT_RUN energy=NOT_MEASURED'
# 1) Чому перевіряємо машинний BSWAP у двох незалежних FPC збірках?
# 2) Чому рівність host результатів не є новим законом SENS?
# 3) Хто видаляє тимчасові FPC units, binary і дизасемблерні логи?
# 4) Чому цей FPC бенчмарк не заявляє прискорення без часу/джоулів?
