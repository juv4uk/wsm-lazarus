#!/usr/bin/env bash
# G6 / #47: фізичний D6:010011 «модуль» — sys_write мусить
# записати ВСІ 3/5 T5M байтів або завершитися кодом 2.
# Host Linux ABI не створює нового SENS закону чи D1-значення.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git fpc timeout mktemp cmp readelf grep objdump; do
  command -v "$tool" >/dev/null || {
    echo "МОДУЛЬ-ЗАПИС-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "МОДУЛЬ-ЗАПИС-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
[[ -w /dev/full ]] || { echo "МОДУЛЬ-ЗАПИС-БЛОК: немає /dev/full" >&2; exit 127; }
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP=$(mktemp -d)
clean() {
  local rc=$? f
  if ((rc != 0)); then
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 28 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap clean EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
# Два bounded FPC збирання; новий workflow або apt не створюється.
for row in 'src/sensd12moduleelf.lpr sensd12moduleelf' \
  'scripts/test-elfd12abs.pas test-elfd12abs'; do
  read -r source output <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$output" \
    "$ROOT/$source" >"$TMP/$output.build" 2>"$TMP/$output.err" || {
      cat "$TMP/$output.build" "$TMP/$output.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$output"
done
timeout 30s "$TMP/bin/test-elfd12abs" "$TMP/physical" >"$TMP/generate.out" \
  2>"$TMP/generate.err"
# 01 — D12, 08 — -2048 -> точно promoted D24.
POS=0
NEG=0
for row in '01 3' '08 5'; do
  read -r tag bytes <<< "$row"
  input="$TMP/physical/$tag-in.sens"
  expected="$TMP/physical/$tag-expected.sens"
  machine="$TMP/$tag.elf"
  test -s "$input" && test -s "$expected"
  timeout 15s "$TMP/bin/sensd12moduleelf" --модуль-D12 "$input" \
    "$machine" >"$TMP/$tag.publish" 2>"$TMP/$tag.err"
  test -x "$machine"
  readelf -h "$machine" | grep -Eq 'Type:[[:space:]]+DYN'
  timeout 5s "$machine" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
  cmp "$expected" "$TMP/$tag.actual.sens"
  test "$(wc -c < "$TMP/$tag.actual.sens")" -eq "$bytes"
  POS=$((POS+1))
  # Фізичний машинний ELF, а не обчислення Pascal чи fake exit status:
  # Linux kernel повертає -EBADF за закритого fd1.
  rc=0
  timeout 5s "$machine" 1>&- 2>"$TMP/$tag.closed.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$tag.closed.err"
  NEG=$((NEG+1))
  # Linux /dev/full повертає -ENOSPC замість byte-count.
  rc=0
  timeout 5s "$machine" >/dev/full 2>"$TMP/$tag.full.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$tag.full.err"
  NEG=$((NEG+1))
done
# Точний x86-64 machine epilogue CMP RAX,OutBytes / JNE:
# не переносити RIP-relative T5M таблиці і не підмінювати математичний CDQ/XOR/SUB.
tail -c +121 "$TMP/08.elf" | objdump -D -b binary -m i386:x86-64 -M intel - \
  >"$TMP/disasm" 2>"$TMP/objdump.err" || {
  # objdump stdin не підтримується в усіх версіях binutils.
  tail -c +121 "$TMP/08.elf" >"$TMP/code.raw"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code.raw" >"$TMP/disasm"
}
grep -Eiq 'cdq' "$TMP/disasm"
grep -Eiq 'cmp[[:space:]]+rax,0x5' "$TMP/disasm"
grep -Eiq 'jne[[:space:]]+' "$TMP/disasm"
test "$POS" -eq 2 && test "$NEG" -eq 4
echo "Д12-МОДУЛЬ-ЗАПИС-ГАРАЗД fpc=checked elf=$POS negatives=$NEG D12=3 D24=5 machine=real oracle=NOT_RUN energy=NOT_MEASURED"
