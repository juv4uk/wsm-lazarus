#!/usr/bin/env bash
# G6.63 — реальний D12 машинний ADD у Linux ELF64, не константна таблиця відповідей.
set -euo pipefail
# Кожна помилка тесту містить команду та рядок; не приховує невдалий ELF.
trap 'echo "ELF-D12-ТЕСТ-ВІДМОВА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ELF-D12-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in fpc timeout cmp readelf objdump grep mktemp; do
  command -v "$exe" >/dev/null || { echo "ELF-D12-БЛОК: відсутній $exe" >&2; exit 127; }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p build/m0.2/d12-elf/units build/m0.2/d12-elf/bin
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
 -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/d12-elf/units" \
 -FE"$ROOT/build/m0.2/d12-elf/bin" -osensd12elf "$ROOT/src/sensd12elf.lpr"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
 -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/d12-elf/units" \
 -FE"$ROOT/build/m0.2/d12-elf/bin" -otest-elfd12add "$ROOT/scripts/test-elfd12add.pas"
CLI="$ROOT/build/m0.2/d12-elf/bin/sensd12elf"
timeout 30s "$ROOT/build/m0.2/d12-elf/bin/test-elfd12add" "$TMP"
PASS=0
for name in 01 02 03 04 05 06 07 08 09; do
  if ! timeout 10s "$CLI" --додати-D12 "$TMP/$name-l.sens" \
    "$TMP/$name-r.sens" "$TMP/$name.elf" >"$TMP/збірка.out" 2>"$TMP/збірка.err"; then
    echo "ELF-D12-ДІАГНОСТИКА: позитивний випадок $name" >&2
    cat "$TMP/збірка.err" >&2
    cat "$TMP/збірка.out" >&2
    exit 1
  fi
  test -x "$TMP/$name.elf"
  test ! -s "$TMP/збірка.err"
  grep -Fq 'machine-add=1' "$TMP/збірка.out"
  readelf -h "$TMP/$name.elf" >"$TMP/заголовок"
  grep -Fq 'DYN (Position-Independent Executable file)' "$TMP/заголовок"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/заголовок"
  timeout 5s "$TMP/$name.elf" >"$TMP/$name-виконано.sens"
  cmp "$TMP/$name-expected.sens" "$TMP/$name-виконано.sens"
  PASS=$((PASS+1))
done
test "$PASS" -eq 9
# Справжня машинна ADD інструкція, а не просте збереження precomputed output.
tail -c +121 "$TMP/02.elf" >"$TMP/інструкції"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/інструкції" >"$TMP/дизасемблювання"
grep -Eiq 'add[[:space:]]+eax,' "$TMP/дизасемблювання"
NEG=0
reject() {
  local target="$TMP/відмовлено-$NEG.elf"
  if timeout 10s "$CLI" "$@" "$target" >"$TMP/частковий.stdout" 2>"$TMP/діагностика.stderr"; then
    echo 'ELF-D12-ПОМИЛКА: хибне джерело прийнято' >&2; exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/частковий.stdout"
  grep -Fq 'ELF-D12-' "$TMP/діагностика.stderr"
  NEG=$((NEG+1))
}
reject --додати-D12 "$TMP/overplus-l.sens" "$TMP/overplus-r.sens"
reject --додати-D12 "$TMP/overminus-l.sens" "$TMP/overminus-r.sens"
reject --додати-D12 "$TMP/bad24.sens" "$TMP/02-r.sens"
reject --додати-D12 "$TMP/bad1.sens" "$TMP/02-r.sens"
reject --додати-D12 "$TMP/bad7.sens" "$TMP/02-r.sens"
reject --додати-D12 "$TMP/corrupt.sens" "$TMP/02-r.sens"
reject --додати-D12 "$TMP/empty.sens" "$TMP/02-r.sens"
reject --додати-D12 "$TMP/missing.sens" "$TMP/02-r.sens"
cp "$TMP/02-l.sens" "$TMP/fake.lisp"
reject --додати-D12 "$TMP/fake.lisp" "$TMP/02-r.sens"
reject --додати-D24 "$TMP/02-l.sens" "$TMP/02-r.sens"
test "$NEG" -eq 10
# No-clobber ціль і фізичний recovery після невдалого admission.
cp "$TMP/01.elf" "$TMP/ціль.elf"
if timeout 10s "$CLI" --додати-D12 "$TMP/02-l.sens" \
  "$TMP/02-r.sens" "$TMP/ціль.elf" >"$TMP/частковий.stdout" 2>"$TMP/діагностика.stderr"; then
  echo 'ELF-D12-ПОМИЛКА: перезапис ELF' >&2; exit 1
fi
cmp "$TMP/ціль.elf" "$TMP/01.elf"
test ! -s "$TMP/частковий.stdout"
timeout 10s "$CLI" --додати-D12 "$TMP/02-l.sens" \
  "$TMP/02-r.sens" "$TMP/відновлений.elf"
timeout 5s "$TMP/відновлений.elf" >"$TMP/відновлений.sens"
cmp "$TMP/02-expected.sens" "$TMP/відновлений.sens"
echo "ELF-D12-ГАРАЗД машинне-додавання=$PASS негативи=$NEG зворотність=точна overflow=fail-closed енергія=не-виміряна"
