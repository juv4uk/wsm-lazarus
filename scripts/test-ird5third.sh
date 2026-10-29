#!/usr/bin/env bash
# G6.67: реальний FPC → verified ExactIR → x86-64 ELF64 → pinned SENS.
# Енергію/джоулі НЕ вимірюємо в GitHub-hosted CI.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D5-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp mktemp python3; do
  command -v "$tool" >/dev/null || { echo "D5-ELF-БЛОК: немає $tool" >&2; exit 127; }
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then echo "D5-ELF-ДІАГНОСТИКА rc=$rc" >&2
  for f in "$TMP"/*.out "$TMP"/*.err "$TMP"/*.log; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 45 "$f" >&2; fi
  done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/d5-data"
for spec in 'scripts/test-ird5third.pas:test-ird5third' \
            'src/sensd5thirdelf.lpr:sensd5thirdelf'; do
  IFS=: read -r source name <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.log" 2>&1 || {
    cat "$TMP/$name.log" >&2; exit 1;
  }
done
# -gh у FPC 3.2.2 може перенаправляти heaptrace через внутрішній
# TextRec. Вимагаємо ЯВНИЙ файл HeapTrc, не приймаємо відсутній звіт.
HEAPTRC="log=$TMP/heaptrace.log" timeout 90s \
  "$TMP/bin/test-ird5third" "$ROOT/external/sens" "$TMP/d5-data" \
  >"$TMP/тести.out" 2>"$TMP/тести.err"
grep -Fq 'D5-ТРЕТЄ-FPC-ГАРАЗД ELF=8 негативи=13' "$TMP/тести.out"
test -s "$TMP/heaptrace.log" || {
  echo 'D5-ELF-ПРОВАЛ: HeapTrc не створив окремий звіт' >&2; exit 1;
}
grep -Fq '0 unfreed memory blocks' "$TMP/heaptrace.log" || {
  echo 'D5-ELF-ПРОВАЛ: HeapTrc не підтвердив нуль витоків' >&2
  cat "$TMP/heaptrace.log" >&2; exit 1;
}
COMP="$TMP/bin/sensd5thirdelf"
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || { echo 'D5-ELF-БЛОК: немає незалежного SENS CLI' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
PASS=0
for i in {0..7}; do
  source="$TMP/d5-data/d5-$i.sens"
  target="$TMP/d5-data/d5-$i.elf"
  original="$TMP/дані/перший-$i.elf"
  cp "$target" "$original"
  rm "$target"
  HEAPTRC="log=$TMP/compile-$i.heap" timeout 20s \
    "$COMP" --третій-ельф "$ROOT/external/sens" \
    "$source" "$target" >"$TMP/compile.out" 2>"$TMP/compile.err"
  test -x "$target"
  cmp "$target" "$original"
  grep -Fq 'D5-ТРЕТЄ-ELF-ГОТОВО' "$TMP/compile.out"
  test -s "$TMP/compile-$i.heap" || {
    echo "D5-ELF-ПРОВАЛ: немає HeapTrc для ELF $i" >&2; exit 1;
  }
  grep -Fq '0 unfreed memory blocks' "$TMP/compile-$i.heap" || {
    echo "D5-ELF-ПРОВАЛ: витоки компілятора $i" >&2
    cat "$TMP/compile-$i.heap" >&2; exit 1;
  }
  readelf -h "$target" >"$TMP/header"
  readelf -l "$target" >"$TMP/segments"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  if grep -E 'INTERP|DYNAMIC' "$TMP/segments"; then
    echo 'D5-ELF-ПРОВАЛ: потрібен самодостатній PIE без loader' >&2; exit 1;
  fi
  tail -c +121 "$target" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" >"$TMP/asm"
  grep -Fq '[rsi+0x10]' "$TMP/asm"
  grep -Fq 'imul' "$TMP/asm"
  timeout 5s "$target" >"$TMP/result.sens"
  cmp "$TMP/result.sens" "$TMP/d5-data/d5-$i.expected.sens"
  timeout 60s "$ORACLE" "$source" >"$TMP/oracle.out" 2>"$TMP/oracle.err" || {
    cat "$TMP/oracle.err" >&2; echo "D5-ELF-ОРАКУЛ-ПРОВАЛ: $i" >&2; exit 1;
  }
  test ! -s "$TMP/oracle.err"
  test "$(tr -d '\r\n' <"$TMP/oracle.out")" = "$((i & 1))" || {
    echo "D5-ELF-ОРАКУЛ-РОЗБІЖНІСТЬ: $i" >&2
    cat "$TMP/oracle.out" >&2; exit 1;
  }
  PASS=$((PASS+1))
done
test "$PASS" -eq 8
# Обов'язкова атомарна відмова (ніякого нового ELF або stdout).
reject() {
  local label="$1" input="$2" rc=0
  timeout 15s "$COMP" --третій-ельф "$ROOT/external/sens" \
    "$input" "$TMP/reject-$label.elf" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  if (( rc != 2 )) || [[ -e "$TMP/reject-$label.elf" ]] || \
      [[ -s "$TMP/reject.out" ]] || \
      ! grep -Fq 'D5-ТРЕТЄ-ELF-ПОМИЛКА:' "$TMP/reject.err"; then
    echo "D5-ELF-НЕГАТИВ: $label rc=$rc" >&2
    cat "$TMP/reject.err" >&2; exit 1
  fi
}
printf '\363' >"$TMP/пошкоджений.sens"
printf '(третє (список так ні так))\n' >"$TMP/людський.lisp"
: >"$TMP/порожній.sens"
reject corrupt "$TMP/пошкоджений.sens"
reject empty "$TMP/порожній.sens"
reject text "$TMP/людський.lisp"
cp "$TMP/d5-data/d5-0.elf" "$TMP/зайнятий.elf"
cp "$TMP/зайнятий.elf" "$TMP/зайнятий.original"
rc=0
timeout 15s "$COMP" --третій-ельф "$ROOT/external/sens" \
  "$TMP/d5-data/d5-1.sens" "$TMP/зайнятий.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
cmp "$TMP/зайнятий.elf" "$TMP/зайнятий.original"
echo 'D5-ТРЕТЄ-НАТИВНЕ-ГАРАЗД ELF=8 оракул=8 негативи=17 x86-64=живий D1=T5M енергія=не-виміряна'
