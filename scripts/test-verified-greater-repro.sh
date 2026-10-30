#!/usr/bin/env bash
# G6: byte-for-byte ELF64 від двох незалежних FPC O1/O2 збірок pinned D5:11011.
# Фізичні .sens — canonical T5M; D7 назви тільки для людини, не dispatch.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout mktemp cmp grep readelf chmod wc seq tail; do
  command -v "$exe" >/dev/null || {
    echo "БІЛЬШЕ-ВІДТВОРЕННЯ-БЛОК: немає $exe" >&2
    exit 127
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(11011 (ук більше?) (укр більше?)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if (( rc != 0 )); then
    echo "БІЛЬШЕ-ВІДТВОРЕННЯ-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
# Окремі units/bin: кожна компіляція повністю відтворює transitive units.
for mode in O1 O2; do
  mkdir -p "$TMP/$mode/bin" "$TMP/$mode/units" "$TMP/$mode/physical"
  timeout 240s fpc -B -Mobjfpc "-$mode" -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$mode/units" -FE"$TMP/$mode/bin" \
    -otest-verified-greater "$ROOT/scripts/test-verified-greater.pas" \
    >"$TMP/$mode-build.log" 2>"$TMP/$mode-build.err"
  test -x "$TMP/$mode/bin/test-verified-greater"
  timeout 720s "$TMP/$mode/bin/test-verified-greater" "$TMP/$mode/physical" \
    >"$TMP/$mode-generator.log" 2>"$TMP/$mode-generator.err"
  grep -Fxq 'VG-PASS physical=16 negatives=9 recovery=1 old-new-elf=identical' \
    "$TMP/$mode-generator.log"
  test "$(wc -l <"$TMP/$mode/physical/cases.tsv")" -eq 16
  if grep -Fq 'unfreed memory blocks' "$TMP/$mode-generator.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/$mode-generator.err"
  else
    test ! -s "$TMP/$mode-generator.err"
  fi
done
# Обидві збірки: ті самі 16 точних T5M-входів та 9 відмов у кожній.
cmp "$TMP/O1/physical/cases.tsv" "$TMP/O2/physical/cases.tsv"
equal=0
executed=0
for sample in $(seq -w 1 16); do
  for suffix in sens expected.sens lisp; do
    cmp "$TMP/O1/physical/$sample.$suffix" \
        "$TMP/O2/physical/$sample.$suffix"
  done
  elf1="$TMP/O1/physical/$sample.elf"
  elf2="$TMP/O2/physical/$sample.elf"
  cmp "$elf1" "$elf2"
  for mode in O1 O2; do
    image="$TMP/$mode/physical/$sample.elf"
    readelf -h "$image" >"$TMP/$mode-$sample-header.log"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$mode-$sample-header.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$mode-$sample-header.log"
    chmod 700 "$image"
    timeout 5s "$image" >"$TMP/$mode-$sample.actual.sens" \
      2>"$TMP/$mode-$sample.machine.err"
    test ! -s "$TMP/$mode-$sample.machine.err"
    cmp "$TMP/$mode/physical/$sample.expected.sens" \
        "$TMP/$mode-$sample.actual.sens"
    executed=$((executed + 1))
  done
  cmp "$TMP/O1-$sample.actual.sens" "$TMP/O2-$sample.actual.sens"
  equal=$((equal + 1))
done
test "$equal" -eq 16
test "$executed" -eq 32
printf 'БІЛЬШЕ-ВІДТВОРЕННЯ-ГАРАЗД pinned=%s O1=16 O2=16 ELF-тотожні=%d машинні-виконання=%d негативи=18 повтори=2 energy=NOT_MEASURED oracle=NOT_RUN\n' \
  "$PIN" "$equal" "$executed"
# Типи: source/result — borrowed exact T5M; ELF — generated host image.
# Тимчасові файлові ресурси належать одному TMP, cleanup за EXIT.
# 1) Чому точна ширина D12 не виводиться з довжини T5M?
# 2) Чим ELF byte-parity сильніша за однакову відповідь D1?
# 3) Чому кожна збірка має окрему директорію FPC units?
# 4) Чому pinned REPL oracle для цієї відтворюваності не заявлено?
# 5) Чому 32 виконання не вимірюють фізичні джоулі?
