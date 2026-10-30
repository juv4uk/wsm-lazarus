#!/usr/bin/env bash
# G6.17: реальне Free Pascal -> Linux x86-64 ELF -> machine execution.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИННА-УМОВА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for invariant in \
  '(cond-clause . (test expression))' \
  '(cond-test . (D1:0 D1:1))' \
  '(cond-on-D1:1 . select-expression)' \
  '(cond-on-D1:0 . continue)' \
  '(cond-after-exhaustion . D3:000)' \
  '(cond-three-part . forbidden)'; do
  grep -Fq "$invariant" external/sens/contracts/language-contract-12.lisp || {
    echo "МАШИННА-УМОВА-БЛОК: немає pinned закону $invariant" >&2; exit 1;
  }
done
grep -Eq '^[[:space:]]*\(110 \(ук за-умовою\) \(укр за-умовою\)' \
  external/sens/lib/domains/d3.lisp || {
  echo 'МАШИННА-УМОВА-БЛОК: D3:110 не підтверджено' >&2; exit 1;
}
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v readelf >/dev/null
mkdir -p build/m0.2/elfcond/units build/m0.2/elfcond/bin
BIN="$ROOT/build/m0.2/elfcond/bin"
UNITS="$ROOT/build/m0.2/elfcond/units"
for row in 'scripts/test-elfcond.pas test-elfcond' \
  'src/senscondelf.lpr senscondelf' \
  'src/sensvykon.lpr sensvykon'; do
  read -r SOURCE TARGET <<< "$row"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$UNITS" -FE"$BIN" "-o$TARGET" "$ROOT/$SOURCE"
done
"$BIN/test-elfcond"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for label in без-гілок одна-істинна одна-істинна-ні одна-хибна \
  дві-друга-істинна дві-перша-істинна дві-хибні \
  три-остання-істинна три-вичерпано \
  шістнадцять-остання-істинна шістнадцять-вичерпано \
  тридцять-дві-остання-істинна тридцять-дві-перша-істинна \
  тридцять-дві-вичерпано \
  рівність-00 рівність-01 рівність-10 рівність-11 \
  дві-рівності-друга дві-рівності-перша \
  тридцять-дві-рівності тридцять-дві-рівності-порожньо \
  вираз-рівність-00 вираз-рівність-01 вираз-рівність-10 вираз-рівність-11 \
  вираз-хибна-гілка вираз-друга-гілка вираз-перша-гілка \
  вираз-тест-і-відповідь вираз-хибний-тест-рівність \
  вираз-тридцять-дві-рівності; do
  INPUT="build/m0.2/elfcond/$label.sens"
  "$BIN/senscondelf" --породити "$INPUT" "$TMP/$label.elf" >"$TMP/$label.compile"
  test -x "$TMP/$label.elf"
  cmp "build/m0.2/elfcond/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  readelf -l "$TMP/$label.elf" >"$TMP/$label.phdr"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.phdr" >/dev/null
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.machine"
  timeout 10s "$BIN/sensvykon" --виконати "$INPUT" >"$TMP/$label.native"
  cmp "$TMP/$label.machine" "$TMP/$label.native"
  cmp "$TMP/$label.machine" "build/m0.2/elfcond/$label.expected.out"
done
# Фізичні та файлові відмови не публікують результат.
printf '\363' >"$TMP/invalid.sens"
for bad in invalid.sens missing.sens; do
  if "$BIN/senscondelf" --породити "$TMP/$bad" "$TMP/rejected.elf" \
      >"$TMP/bad.out" 2>"$TMP/bad.err"; then
    echo 'МАШИННА-УМОВА-ПОМИЛКА: хибний .sens прийнято' >&2; exit 1
  fi
  test ! -e "$TMP/rejected.elf"
  test ! -s "$TMP/bad.out"
  grep -F 'МАШИННА-УМОВА-ПОМИЛКА' "$TMP/bad.err" >/dev/null
done
printf '(за-умовою (так ні))\n' >"$TMP/human.lisp"
if "$BIN/senscondelf" --породити "$TMP/human.lisp" "$TMP/human.elf" \
    >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННА-УМОВА-ПОМИЛКА: .lisp видано за .sens' >&2; exit 1
fi
test ! -s "$TMP/bad.out"
test ! -e "$TMP/human.elf"
printf 'не-перезаписувати\n' >"$TMP/occupied.elf"
cp "$TMP/occupied.elf" "$TMP/unchanged"
if "$BIN/senscondelf" --породити \
    'build/m0.2/elfcond/одна-істинна.sens' "$TMP/occupied.elf" \
    >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'МАШИННА-УМОВА-ПОМИЛКА: перезапис існуючого ELF' >&2; exit 1
fi
cmp "$TMP/occupied.elf" "$TMP/unchanged"
test ! -s "$TMP/bad.out"
echo 'МАШИННА-УМОВА-ЕЛФ-ГАРАЗД FPC=так ELF64=x86-64 D3:110=CMP/JNE 32-виконання=так CMP/SETE/MOVZX=так негативні=26 upstream-REPL=не-доведено'
