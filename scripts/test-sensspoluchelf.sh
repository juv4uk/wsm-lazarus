#!/usr/bin/env bash
# G6.65 — AOT constant folding: pinned D3:111 → Linux x86-64 PIE → T5M.
# Цей тест НЕ є енергетичним виміром або загальним компілятором.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'СПОЛУЧЕННЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in fpc readelf python3 timeout cmp mktemp; do
  command -v "$cmd" >/dev/null || { echo "СПОЛУЧЕННЯ-БЛОК: $cmd" >&2; exit 127; }
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.err "$TMP"/*.log; do if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 35 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
for source in 'src/senst5m.lpr:senst5m' 'src/sensvykon.lpr:sensvykon' 'src/sensspoluchelf.lpr:sensspoluchelf'; do
  IFS=: read -r path name <<< "$source"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" "-o$name" "$ROOT/$path" \
    >"$TMP/build-$name.log" 2>&1 || { cat "$TMP/build-$name.log" >&2; exit 1; }
done
PACK="$TMP/bin/senst5m"
EXEC="$TMP/bin/sensvykon"
COMP="$TMP/bin/sensspoluchelf"
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'СПОЛУЧЕННЯ-БЛОК: незалежний pinned SENS CLI не зібрано' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
POSITIVE=0
for entry in '00:0:0' '01:0:1' '10:1:0' '11:1:1' '0e:0:000' '1e:1:000'; do
  IFS=: read -r label left right <<< "$entry"
  printf '10 111 %s %s 01\n' "$left" "$right" >"$TMP/$label.words"
  timeout 10s "$PACK" --пакувати-слова "$TMP/$label.words" >"$TMP/$label.sens"
  timeout 10s "$EXEC" --виконати-сенс "$TMP/$label.sens" \
    >"$TMP/$label.expected.sens" 2>"$TMP/$label.exec.err"
  test -s "$TMP/$label.expected.sens"
  test ! -s "$TMP/$label.exec.err"
  timeout 10s "$COMP" --згорнути-сполучення "$ROOT/external/sens" \
    "$TMP/$label.sens" "$TMP/$label.elf" \
    >"$TMP/$label.log" 2>"$TMP/$label.compile.err"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/header"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/$label.expected.sens" "$TMP/$label.actual.sens"
  # Незалежний pinned SENS справді виконує точно ці самі фізичні байти.
  timeout 40s "$ORACLE" "$TMP/$label.sens" >"$TMP/$label.upstream" \
    2>"$TMP/$label.upstream.err" || {
      echo "СПОЛУЧЕННЯ-ОРАКУЛ-ПРОВАЛ $label" >&2
      cat "$TMP/$label.upstream.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.upstream.err"
  timeout 10s "$EXEC" --виконати "$TMP/$label.sens" >"$TMP/$label.fpc-human"
  if ! cmp -s "$TMP/$label.fpc-human" "$TMP/$label.upstream"; then
    echo "СПОЛУЧЕННЯ-ОРАКУЛ-РОЗБІЖНІСТЬ $label" >&2
    echo 'FPC:' >&2; cat "$TMP/$label.fpc-human" >&2
    echo 'upstream:' >&2; cat "$TMP/$label.upstream" >&2; exit 1
  fi
  POSITIVE=$((POSITIVE+1))
done

# Незмінність ELF при відмові публікації у вже існуючий файл.
cp "$TMP/00.elf" "$TMP/existing.original.elf"
cp "$TMP/00.elf" "$TMP/existing.elf"
NEG=0
reject() {
  local label="$1" in_path="$2" out="$TMP/rejected-$1.elf" rc=0
  timeout 15s "$COMP" --згорнути-сполучення "$ROOT/external/sens" \
    "$in_path" "$out" >"$TMP/fail.out" 2>"$TMP/fail.err" || rc=$?
  if ((rc != 2)) || [[ -e "$out" ]] || [[ -s "$TMP/fail.out" ]] || \
     ! grep -Fq 'СПОЛУЧЕННЯ-ELF-ПОМИЛКА:' "$TMP/fail.err"; then
    echo "СПОЛУЧЕННЯ-НЕГАТИВ-ПРОВАЛ $label rc=$rc" >&2
    cat "$TMP/fail.err" >&2; exit 1
  fi
  NEG=$((NEG+1))
}
make_bad() {
  local label="$1" words="$2"
  printf '%s\n' "$words" >"$TMP/$label.words"
  "$PACK" --пакувати-слова "$TMP/$label.words" >"$TMP/$label.sens"
}
make_bad wronghead '10 101 0 1 01'
make_bad arity '10 111 0 01'
make_bad extra '10 111 0 1 1 01'
make_bad d7 '10 111 0010110 1 01'
make_bad d12 '10 111 000000000000 1 01'
make_bad nested '10 111 0 10 1 01 01'
make_bad dot '10 111 0 11 1 01'
printf '\363' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
printf '(сполучити так ні)\n' >"$TMP/text.lisp"
for label in wronghead arity extra d7 d12 nested dot corrupt empty; do
  reject "$label" "$TMP/$label.sens"
done
reject text "$TMP/text.lisp"
rc=0
timeout 10s "$COMP" --згорнути-сполучення "$ROOT/external/sens" \
  "$TMP/00.sens" "$TMP/existing.elf" >"$TMP/fail.out" 2>"$TMP/fail.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/fail.out"
cmp "$TMP/existing.elf" "$TMP/existing.original.elf"
NEG=$((NEG+1))
rc=0
timeout 10s "$COMP" --помилковий-режим "$ROOT/external/sens" \
  "$TMP/00.sens" "$TMP/nope.elf" >"$TMP/fail.out" 2>"$TMP/fail.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/fail.out" && test ! -e "$TMP/nope.elf"
NEG=$((NEG+1))
test "$POSITIVE" -eq 6 && test "$NEG" -eq 12
echo "СПОЛУЧЕННЯ-НАTИВНЕ-ГАРАЗД FPC=так ELF=$POSITIVE негативи=$NEG T5M=побайтово oracle=pinned-SENS AOT=стале-значення енергія=не-виміряна"
