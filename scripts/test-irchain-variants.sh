#!/usr/bin/env bash
# G6.142 — інший порядок 100-крокового D5 без другого компілятора.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for t in git fpc timeout cmp mktemp readelf objdump grep awk dd python3;do
  command -v "$t" >/dev/null || { echo "D5-ВАРІАНТИ-БЛОК: немає $t" >&2;exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'D5-ВАРІАНТИ-БЛОК: незалежний pinned SENS oracle відсутній' >&2;exit 127;
}
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc!=0)); then echo "D5-ВАРІАНТИ-ПРОВАЛ rc=$rc line=$LINENO" >&2; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/u" "$TMP/cases"
for spec in \
  'scripts/test-irchain-variants.pas:test-irchain-variants' \
  'src/sensarithchainelf.lpr:sensarithchainelf' \
  'src/senschyslo.lpr:senschyslo';do
  IFS=: read -r path name <<< "$spec"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/bin" "-o$name" \
      "$ROOT/$path" >"$TMP/$name.build.log" 2>"$TMP/$name.build.err";then
    cat "$TMP/$name.build.log" "$TMP/$name.build.err" >&2;exit 1
  fi
  test -x "$TMP/bin/$name"
done
timeout 120s "$TMP/bin/test-irchain-variants" "$TMP/cases" \
  >"$TMP/manifest.tsv" 2>"$TMP/gen.err"
grep -Fxq 'D5-VARIANTS-UNIT-OK positive=12 negative=7 depths=1,25,50,100' "$TMP/gen.err"
test "$(wc -l <"$TMP/manifest.tsv")" -eq 12
passed=0
while IFS=$'\t' read -r tag depth variant wanted;do
  [[ -n "$tag" && -n "$wanted" ]] || exit 1
  base="$TMP/cases/$tag"
  compiled="$TMP/$tag.elf"
  timeout 30s "$TMP/bin/sensarithchainelf" --ланцюг-D5 \
    "$base.sens" "$compiled" >"$TMP/$tag.compile.out" 2>"$TMP/$tag.compile.err"
  test -x "$compiled"
  grep -Fq 'D5-ARITH-CHAIN-ELF64' "$TMP/$tag.compile.out"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.compile.err"
  timeout 5s readelf -h "$compiled" >"$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
  if readelf -l "$compiled" | grep -Eq 'INTERP|DYNAMIC'; then
    echo 'помилка: сторонній динамічний runtime ELF' >&2;exit 1
  fi
  chmod 500 "$compiled"
  timeout 10s "$compiled" >"$TMP/$tag.machine.sens" 2>"$TMP/$tag.machine.err"
  test ! -s "$TMP/$tag.machine.err"
  cmp "$base.expected.sens" "$TMP/$tag.machine.sens"
  test "$(wc -c <"$TMP/$tag.machine.sens")" -eq 3
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 "$TMP/$tag.machine.sens" \
    >"$TMP/$tag.machine.ukr"
  printf '%s\n' "$wanted" >"$TMP/$tag.wanted"
  cmp "$TMP/$tag.wanted" "$TMP/$tag.machine.ukr"

  # Лише фізична машинна частина MOV EAX,base + depth*(ADD|SUB EAX,imm32).
  dd if="$compiled" of="$TMP/$tag.code" bs=1 skip=120 \
    count=$((5+5*depth)) status=none
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$tag.code" >"$TMP/$tag.asm"
  grep -Eio '(add|sub)[[:space:]]+eax,' "$TMP/$tag.asm" |
    awk '{print $1}' >"$TMP/$tag.machine.ops"
  : >"$TMP/$tag.expected.ops"
  for ((k=0;k<depth;k++));do
    case $(((k+variant)%7)) in
       0|2|3|6) printf 'add\n' >>"$TMP/$tag.expected.ops";;
       *) printf 'sub\n' >>"$TMP/$tag.expected.ops";;
    esac
  done
  cmp "$TMP/$tag.expected.ops" "$TMP/$tag.machine.ops"

  # Це інша програма, не FPC evaluator і не текстове джерело ISA:
  # pinned Rust/Zig SENS отримує тільки укр-проєкцію тієї ж форми.
  timeout 70s "$ORACLE" "$base.lisp" \
    >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
  test ! -s "$TMP/$tag.oracle.err"
  cmp "$TMP/$tag.oracle.out" "$TMP/$tag.machine.ukr"
  passed=$((passed+1))
done <"$TMP/manifest.tsv"
test "$passed" -eq 12

rejected=0
for name in bad-head bad-width bad-depth bad-truncated bad-two-roots bad-corrupt bad-empty;do
  bad="$TMP/cases/$name.sens"
  test -f "$bad"
  out="$TMP/$name.elf"
  rc=0
  timeout 30s "$TMP/bin/sensarithchainelf" --ланцюг-D5 "$bad" "$out" \
    >"$TMP/$name.out" 2>"$TMP/$name.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$out" && test ! -L "$out"
  test ! -s "$TMP/$name.out"
  grep -Fq 'ВІДМОВА:' "$TMP/$name.err"
  rejected=$((rejected+1))
done
test "$rejected" -eq 7

# Атомарна no-clobber publication — існуючу програму не змінюємо.
cp "$TMP/1-0.elf" "$TMP/occupied.elf"
rc=0
timeout 30s "$TMP/bin/sensarithchainelf" --ланцюг-D5 \
  "$TMP/cases/1-1.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/1-0.elf" "$TMP/occupied.elf"
# Один файл із людською проєкцією НЕ є канонічним входом до native CLI.
rc=0
timeout 30s "$TMP/bin/sensarithchainelf" --ланцюг-D5 \
  "$TMP/cases/1-0.lisp" "$TMP/forbidden.elf" \
  >"$TMP/forbidden.out" 2>"$TMP/forbidden.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/forbidden.elf"
echo "D5-VARIANTS-OK physical=12 machine=12 independent-sens=12 irregular-op=1,25,50,100 negative=7 no-clobber=yes energy=NOT-MEASURED"
