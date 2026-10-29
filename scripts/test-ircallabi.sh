#!/usr/bin/env bash
# G6.69 — виконуваний Linux PIE із справжніми CALL/RET, не тільки IR.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ABI-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for command_name in fpc timeout readelf objdump cmp stat git; do
  command -v "$command_name" >/dev/null || {
    echo "ABI-БЛОК: не встановлено $command_name" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.err "$TMP"/*.log; do if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 30 "$f" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
for entry in \
  'src/sensabielf.lpr:sensabielf' \
  'src/sensvykon.lpr:sensvykon' \
  'src/senst5m.lpr:senst5m' \
  'scripts/test-sensmashyna.pas:test-sensmashyna'; do
  IFS=: read -r source name <<< "$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" "-o$name" "$ROOT/$source" \
    >"$TMP/build-$name.log" 2>&1 || {
      cat "$TMP/build-$name.log" >&2; exit 1;
    }
done
timeout 30s "$TMP/bin/test-sensmashyna" "$ROOT/external/sens" "$TMP" \
  >"$TMP/fixtures.out"
grep -Fq 'МАШИНА-СВІДКИ-ГАРАЗД' "$TMP/fixtures.out"
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
POS=0
for label in тотожні-00 тотожні-01 тотожні-10 тотожні-11; do
  elf="$TMP/$label.elf"
  timeout 20s "$TMP/bin/sensabielf" --виклик-рівності \
    "$ROOT/external/sens" "$TMP/$label.sens" "$elf" \
    >"$TMP/$label.log" 2>"$TMP/$label.err"
  test ! -s "$TMP/$label.err"
  test -x "$elf"
  test "$(stat -c %a "$elf")" = 700
  readelf -h "$elf" >"$TMP/header"
  readelf -l "$elf" >"$TMP/program"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  grep -Fq LOAD "$TMP/program"
  tail -c +121 "$elf" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" >"$TMP/asm"
  for mnemonic in 'call' 'ret' 'sete' 'cmp' 'syscall'; do
    grep -Fq "$mnemonic" "$TMP/asm" || {
      echo "ABI-ПРОВАЛ: немає машинної інструкції $mnemonic" >&2; exit 1;
    }
  done
  timeout 5s "$elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/$label.expected.sens" "$TMP/$label.actual.sens"
  timeout 20s "$ORACLE" "$TMP/$label.sens" >"$TMP/$label.oracle" \
    2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  timeout 10s "$TMP/bin/sensvykon" --виконати "$TMP/$label.sens" \
    >"$TMP/$label.fpc"
  cmp "$TMP/$label.oracle" "$TMP/$label.fpc"
  POS=$((POS+1))
done

NEG=0
reject() {
  local label="$1" input="$2" output="$TMP/rejected-$label.elf" rc=0
  timeout 20s "$TMP/bin/sensabielf" --виклик-рівності \
    "$ROOT/external/sens" "$input" "$output" >"$TMP/reject.out" \
    2>"$TMP/reject.err" || rc=$?
  if ((rc != 2)) || [[ -e "$output" ]] || [[ -s "$TMP/reject.out" ]] || \
     ! grep -Fq 'ABI-ELF-ПОМИЛКА:' "$TMP/reject.err"; then
    echo "ABI-НЕГАТИВ-ПРОВАЛ: $label код=$rc" >&2
    cat "$TMP/reject.err" >&2; exit 1
  fi
  NEG=$((NEG+1))
}
for label in помилковий-байт незакрита-форма хибний-д12 порожній; do
  reject "$label" "$TMP/$label.sens"
done
for row in \
  'сполучити:10 111 0 0 01' \
  'без-аргументу:10 101 01' \
  'один-аргумент:10 101 0 01' \
  'зайвий-аргумент:10 101 0 0 1 01' \
  'лівий-д7:10 101 0010110 0 01' \
  'правий-д7:10 101 0 0010110 01' \
  'порожнеча:10 101 000 0 01' \
  'крапкова-пара:10 101 11 0 1 01'; do
  label="${row%%:*}"; words="${row#*:}"
  printf '%s\n' "$words" >"$TMP/$label.words"
  "$TMP/bin/senst5m" --пакувати-слова "$TMP/$label.words" \
    >"$TMP/$label.sens"
  reject "$label" "$TMP/$label.sens"
done
printf '(тотожне? так ні)\n' >"$TMP/текст.lisp"
reject "текст" "$TMP/текст.lisp"
cp "$TMP/тотожні-00.sens" "$TMP/фальшивий.lisp"
reject "підроблений" "$TMP/фальшивий.lisp"
cp "$TMP/тотожні-00.elf" "$TMP/незмінний.elf"
cp "$TMP/незмінний.elf" "$TMP/незмінний.original.elf"
rc=0
timeout 10s "$TMP/bin/sensabielf" --виклик-рівності \
  "$ROOT/external/sens" "$TMP/тотожні-00.sens" "$TMP/незмінний.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
cmp "$TMP/незмінний.elf" "$TMP/незмінний.original.elf"
NEG=$((NEG+1))
rc=0
timeout 10s "$TMP/bin/sensabielf" --невідомий \
  "$ROOT/external/sens" "$TMP/тотожні-00.sens" "$TMP/невідомий.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
test ! -e "$TMP/невідомий.elf"
NEG=$((NEG+1))
test "$POS" -eq 4 && test "$NEG" -eq 16
echo "ABI-ELF-ГАРАЗД machine=CALL/RET/CMP/SETE FPC=реальний ELF=$POS негативи=$NEG T5M=byte-exact oracle=pinned-SENS режим=тільки-D3:101 енергія=не-виміряна"
