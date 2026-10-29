#!/usr/bin/env bash
# G6.63 — реальний D12 машинний ADD у Linux ELF64, не константна таблиця відповідей.
set -euo pipefail
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
for name in нуль плюс мінус два-мінус край перенесення скасування максимум мінімум; do
  timeout 10s "$CLI" --додати-D12 "$TMP/$name-ліве.sens" \
    "$TMP/$name-праве.sens" "$TMP/$name.elf" >"$TMP/збірка.out" 2>"$TMP/збірка.err"
  test -x "$TMP/$name.elf"
  test ! -s "$TMP/збірка.err"
  grep -Fq 'machine-add=так' "$TMP/збірка.out"
  readelf -h "$TMP/$name.elf" >"$TMP/заголовок"
  grep -Fq 'DYN (Position-Independent Executable file)' "$TMP/заголовок"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/заголовок"
  timeout 5s "$TMP/$name.elf" >"$TMP/$name-виконано.sens"
  cmp "$TMP/$name-результат.sens" "$TMP/$name-виконано.sens"
  PASS=$((PASS+1))
done
test "$PASS" -eq 9
# Справжня машинна ADD інструкція, а не просте збереження precomputed output.
tail -c +121 "$TMP/плюс.elf" >"$TMP/інструкції"
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
reject --додати-D12 "$TMP/переповнення-ліве.sens" "$TMP/переповнення-праве.sens"
reject --додати-D12 "$TMP/під-межею-ліве.sens" "$TMP/під-межею-праве.sens"
reject --додати-D12 "$TMP/чужий-d24.sens" "$TMP/плюс-праве.sens"
reject --додати-D12 "$TMP/чужий-d1.sens" "$TMP/плюс-праве.sens"
reject --додати-D12 "$TMP/чужий-d7.sens" "$TMP/плюс-праве.sens"
reject --додати-D12 "$TMP/пошкоджений.sens" "$TMP/плюс-праве.sens"
reject --додати-D12 "$TMP/порожній.sens" "$TMP/плюс-праве.sens"
reject --додати-D12 "$TMP/неіснує.sens" "$TMP/плюс-праве.sens"
cp "$TMP/плюс-ліве.sens" "$TMP/підробка.lisp"
reject --додати-D12 "$TMP/підробка.lisp" "$TMP/плюс-праве.sens"
reject --додати-D24 "$TMP/плюс-ліве.sens" "$TMP/плюс-праве.sens"
test "$NEG" -eq 10
# No-clobber ціль і фізичний recovery після невдалого admission.
cp "$TMP/нуль.elf" "$TMP/ціль.elf"
if timeout 10s "$CLI" --додати-D12 "$TMP/плюс-ліве.sens" \
  "$TMP/плюс-праве.sens" "$TMP/ціль.elf" >"$TMP/частковий.stdout" 2>"$TMP/діагностика.stderr"; then
  echo 'ELF-D12-ПОМИЛКА: перезапис ELF' >&2; exit 1
fi
cmp "$TMP/ціль.elf" "$TMP/нуль.elf"
test ! -s "$TMP/частковий.stdout"
timeout 10s "$CLI" --додати-D12 "$TMP/плюс-ліве.sens" \
  "$TMP/плюс-праве.sens" "$TMP/відновлений.elf"
timeout 5s "$TMP/відновлений.elf" >"$TMP/відновлений.sens"
cmp "$TMP/плюс-результат.sens" "$TMP/відновлений.sens"
echo "ELF-D12-ГАРАЗД машинне-додавання=$PASS негативи=$NEG зворотність=точна overflow=fail-closed енергія=не-виміряна"
