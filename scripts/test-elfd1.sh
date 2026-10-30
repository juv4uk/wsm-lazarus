#!/usr/bin/env bash
# G6.8 — виконати справжній ELF64 x86-64 Linux, порівняти із pinned SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -m)" == x86_64 && "$(uname -s)" == Linux ]] || {
  echo 'НАТИВНИЙ-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 1;
}
FPC_BIN=${FPC:-fpc}
mkdir -p build/m0.2/elfd1/units build/m0.2/elfd1/bin
for target in test-elfd1 senself sensvykon; do
  if [[ $target == test-elfd1 ]]; then source=scripts/test-elfd1.pas
  else source=src/$target.lpr
  fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/elfd1/units" -FE"$ROOT/build/m0.2/elfd1/bin" \
    -o"$target" "$source"
done
./build/m0.2/elfd1/bin/test-elfd1
BIN="$ROOT/build/m0.2/elfd1/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for bit in 0 1; do
  if [[ $bit == 0 ]]; then label=zero; else label=one; fi
  src="build/m0.2/elfd1/$bit.sens"
  "$BIN/senself" --породити "$src" "$TMP/$label.elf" >"$TMP/$label.compile"
  test -x "$TMP/$label.elf"
  test "$(stat -c %s "$TMP/$label.elf")" = 172
  cmp "build/m0.2/elfd1/$label.expected.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  readelf -l "$TMP/$label.elf" > "$TMP/$label.program"
  grep -F 'ELF64' "$TMP/$label.header" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$label.header" >/dev/null
  grep -F 'EXEC (Executable file)' "$TMP/$label.header" >/dev/null
  grep -F 'LOAD' "$TMP/$label.program" >/dev/null
  "$TMP/$label.elf" > "$TMP/$label.native"
  "$BIN/sensvykon" --виконати "$src" > "$TMP/$label.reference"
  cmp "$TMP/$label.native" "$TMP/$label.reference"
  printf '%s\n' "$bit" > "$TMP/$label.expected"
  cmp "$TMP/$label.native" "$TMP/$label.expected"
done

# Незалежний машинний ET_DYN, без PT_INTERP, RIP-relative x86-64.
for bit in 0 1; do
  if [[ $bit == 0 ]]; then label=zero; else label=one; fi
  src="build/m0.2/elfd1/$bit.sens"
  "$BIN/senself" --породити-переміщуваний "$src" "$TMP/$label.pie.elf" >"$TMP/$label.pie.compile"
  "$BIN/senself" --породити-переміщуваний "$src" "$TMP/$label.pie.again.elf" >"$TMP/$label.pie.again.compile"
  test -x "$TMP/$label.pie.elf"
  cmp "$TMP/$label.pie.elf" "$TMP/$label.pie.again.elf"
  cmp "build/m0.2/elfd1/$label.expected.elf.pie" "$TMP/$label.pie.elf"
  test "$(stat -c %s "$TMP/$label.pie.elf")" = 172
  readelf -h "$TMP/$label.pie.elf" > "$TMP/$label.pie.header"
  readelf -l "$TMP/$label.pie.elf" > "$TMP/$label.pie.program"
  grep -E 'Type:.*DYN' "$TMP/$label.pie.header" >/dev/null
  grep -E 'Entry point address:.*0x78' "$TMP/$label.pie.header" >/dev/null
  grep -E '^  LOAD[[:space:]]+0x0{16}[[:space:]]+0x0{16}' "$TMP/$label.pie.program" >/dev/null
  if grep -E 'INTERP|DYNAMIC' "$TMP/$label.pie.program" >/dev/null; then
    echo 'НАТИВНИЙ-PIE-ПОМИЛКА: сторонній інтерпретатор ELF' >&2; exit 1
  fi
  "$TMP/$label.pie.elf" > "$TMP/$label.pie.native"
  "$BIN/sensvykon" --виконати "$src" > "$TMP/$label.pie.reference"
  cmp "$TMP/$label.pie.native" "$TMP/$label.pie.reference"
  printf '%s\n' "$bit" > "$TMP/$label.pie.expected"
  cmp "$TMP/$label.pie.native" "$TMP/$label.pie.expected"
done

printf '\363' > "$TMP/bad.sens"
printf 'збережений-файл\n' > "$TMP/existing.elf"
# Третій фізичний результат: порожня D3:000, НЕ D1:0.
"$BIN/senself" --породити build/m0.2/elfd1/empty.sens "$TMP/empty.elf" >"$TMP/empty.compile"
test -x "$TMP/empty.elf"
test "$(stat -c %s "$TMP/empty.elf")" = 173
cmp build/m0.2/elfd1/empty.expected.elf "$TMP/empty.elf"
readelf -h "$TMP/empty.elf" >"$TMP/empty.header"
readelf -l "$TMP/empty.elf" >"$TMP/empty.program"
grep -F 'ELF64' "$TMP/empty.header" >/dev/null
grep -F 'EXEC (Executable file)' "$TMP/empty.header" >/dev/null
grep -F 'LOAD' "$TMP/empty.program" >/dev/null
"$TMP/empty.elf" >"$TMP/empty.native"
"$BIN/sensvykon" --виконати build/m0.2/elfd1/empty.sens >"$TMP/empty.reference"
printf '()\n' > "$TMP/empty.expected"
cmp "$TMP/empty.native" "$TMP/empty.expected"
cmp "$TMP/empty.native" "$TMP/empty.reference"
! cmp -s "$TMP/empty.native" "$TMP/zero.native"

for input in "$TMP/bad.sens" "build/m0.2/elfd1/many.sens" "build/m0.2/elfd1/quote.sens"; do
  if "$BIN/senself" --породити "$input" "$TMP/rejected.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo "НАТИВНИЙ-ELF-ПОМИЛКА: непідтриманий $input став executable" >&2; exit 1
  fi
  test ! -e "$TMP/rejected.elf"
  test ! -s "$TMP/bad.stdout"
  grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА' "$TMP/bad.stderr" >/dev/null
done
# ET_DYN так само зобов'язаний відхиляти непідтриману фізичну SENS
# без побічного ELF-файлу і без часткового stdout.
for input in "$TMP/bad.sens" "build/m0.2/elfd1/many.sens" "build/m0.2/elfd1/quote.sens"; do
  if "$BIN/senself" --породити-переміщуваний "$input" "$TMP/rejected.pie.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
    echo "НАТИВНИЙ-PIE-ПОМИЛКА: непідтриманий $input став executable" >&2; exit 1
  fi
  test ! -e "$TMP/rejected.pie.elf"
  test ! -s "$TMP/bad.stdout"
  grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА' "$TMP/bad.stderr" >/dev/null
done
if "$BIN/senself" --породити build/m0.2/elfd1/0.sens "$TMP/existing.elf" >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
  echo 'НАТИВНИЙ-ELF-ПОМИЛКА: перезаписав наявний файл' >&2; exit 1
fi
printf 'збережений-файл\n' > "$TMP/existing.expected"
cmp "$TMP/existing.elf" "$TMP/existing.expected"
test ! -s "$TMP/bad.stdout"
# G6.31: race/no-clobber. Для dangling symlink FileExists=false,
# тому старий RenameFile перезаписував навіть уже зайняте ім'я.
# Обидва реальні ELF режими зобов'язані відхиляти без жодного запису.
for mode in --породити --породити-переміщуваний; do
  target="$TMP/ціль-$mode.elf"
  occupied="$TMP/зайнято-$mode.elf"
  broken="$TMP/посилання-$mode.elf"
  printf 'ПРОВІРКА-НЕЗМІННОСТІ\n' > "$occupied"
  printf 'ПРОВІРКА-НЕЗМІННОСТІ\n' > "$TMP/еталон-$mode"
  ln -s "$target" "$broken"
  for output in "$occupied" "$broken"; do
    if "$BIN/senself" "$mode" build/m0.2/elfd1/0.sens "$output" \
        >"$TMP/bad.stdout" 2>"$TMP/bad.stderr"; then
      echo "НАТИВНИЙ-ELF-ПОМИЛКА: перезаписано $output ($mode)" >&2; exit 1
    fi
    test ! -s "$TMP/bad.stdout"
    grep -F 'НАТИВНИЙ-ELF-ПОМИЛКА:' "$TMP/bad.stderr" >/dev/null
  done
  cmp "$occupied" "$TMP/еталон-$mode"
  test -L "$broken"
  test "$(readlink "$broken")" = "$target"
  test ! -e "$target"
done
# Тільки наші тимчасові "sen..." файли, жодного чужого/застарілого.
if find "$TMP" -maxdepth 1 -type f -name 'sen*' -print -quit | grep -q .; then
  echo 'НАТИВНИЙ-ELF-ПОМИЛКА: залишено тимчасовий файл' >&2; exit 1
fi
# G6.225: реально виконуємо всі п'ять ELF після короткого/невдалого
# host stdout. Позитивне обчислення НЕ доводить повного sys_write.
# Тут ASCII/LF — давня host-проєкція виконаного фізичного SENS, а
# вхід лишається канонічним packed .sens T5M із точним доменом.
# 1) Чому D3:000 не дорівнює D1:0?
# 2) Чому EBADF і ENOSPC мають host exit=2?
# 3) Чому ET_DYN та ET_EXEC ділять той самий машинний епілог?
# 4) Де перевіряється незалежний фізичний executor?
for target in zero.elf one.elf zero.pie.elf one.pie.elf empty.elf; do
  ELF="$TMP/$target"
  dd if="$ELF" of="$TMP/epilogue.code" bs=1 skip=120 count=50 status=none
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/epilogue.code" >"$TMP/epilogue.dis"
  grep -Eiq 'cmp[[:space:]]+rax,rdx' "$TMP/epilogue.dis"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/epilogue.dis"
  grep -Eiq 'mov[[:space:]]+edi,0x2' "$TMP/epilogue.dis"
done
WRITE_BAD=0
WRITE_RECOVERY=0
for target in zero.elf one.elf zero.pie.elf one.pie.elf empty.elf; do
  ELF="$TMP/$target"
  case "$target" in
    zero*)  printf '0\\n' >"$TMP/record.expected" ;;
    one*)   printf '1\\n' >"$TMP/record.expected" ;;
    empty*) printf '()\\n' >"$TMP/record.expected" ;;
  esac
  status=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/host.err" || status=$?
  test "$status" -eq 2 && test ! -s "$TMP/host.err"
  WRITE_BAD=$((WRITE_BAD+1))
  status=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/host.err" || status=$?
  test "$status" -eq 2 && test ! -s "$TMP/host.err"
  WRITE_BAD=$((WRITE_BAD+1))
  timeout 5s "$ELF" >"$TMP/recovered.actual" 2>"$TMP/host.err"
  cmp "$TMP/record.expected" "$TMP/recovered.actual"
  test ! -s "$TMP/host.err"
  WRITE_RECOVERY=$((WRITE_RECOVERY+1))
done
test "$WRITE_BAD" -eq 10 && test "$WRITE_RECOVERY" -eq 5
echo "НАТИВНИЙ-ЛІТЕРАЛ-ЗАПИС-ГАРАЗД host-негативи=$WRITE_BAD відновлення=$WRITE_RECOVERY ET_EXEC=так ET_DYN=так D1=0,1 D3:000=()"
echo 'НАТИВНИЙ-ELF-БЕЗ-ПЕРЕЗАПИСУ-ГАРАЗД ET_EXEC=так ET_DYN=так symlink=збережено файл=збережено temp=немає'
echo 'НАТИВНИЙ-ELF-ВИКОНАННЯ-ГАРАЗД ELF64=x86-64 ET_EXEC=так ET_DYN=так PIE=виконано runtime=машинний D1=0,1 D3:000=() differential=сенсвикон відмова=без-файлу'
