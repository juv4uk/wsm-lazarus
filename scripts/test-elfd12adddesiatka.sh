#!/usr/bin/env bash
# G6.x — «(додати 2 3)» як СПРАВЖНЯ машинна інструкція add у Linux ELF64,
# а не надрукована константа.
#
# Що саме доводиться:
#   1. ELF збирається з канонічної текстової форми «(додати 2 3)».
#   2. Запуск ELF дає рівно байти «5\n» — без жодного Pascal-обчислення
#      під час друку.
#   3. Позитивний свідок: у машинному коді фізично лежать байти add
#      (01 D8) і безпосередні операнди 2 та 3, а не сума.
#   4. Негативний свідок: той самий образ із зіпсованим опкодом add
#      дає НЕ «5». Отже число справді залежить від інструкції.
set -euo pipefail
trap 'echo "ELF-D12-ДЕСЯТКОВО-ТЕСТ-ВІДМОВА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ELF-D12-ДЕСЯТКОВО-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for exe in fpc timeout cmp od dd cat mktemp; do
  command -v "$exe" >/dev/null || {
    echo "ELF-D12-ДЕСЯТКОВО-БЛОК: відсутній $exe" >&2; exit 127; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/u" "$TMP/b" "$TMP/w"

FPC_BIN=${FPC:-fpc}
timeout 240s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" \
  -osensd12adddesiatka "$ROOT/src/sensd12adddesiatka.lpr"
timeout 240s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" \
  -otest-elfd12adddesiatka "$ROOT/scripts/test-elfd12adddesiatka.pas"

CLI="$TMP/b/sensd12adddesiatka"
HELPER="$TMP/b/test-elfd12adddesiatka"

# Текстові форми й очікуваний stdout; розбирач перевіряється окремо.
timeout 30s "$HELPER" "$TMP/w"

# --- 1. Позитивні випадки: збірка, запуск, точний stdout ---------------
PASS=0
RC=0
for name in 01 02 03 04 05 06; do
  PROG=$(cat "$TMP/w/$name.prohrama")
  if ! timeout 30s "$CLI" --додати-десятково "$PROG" "$TMP/$name.elf" \
      >"$TMP/$name.build.out" 2>"$TMP/$name.build.err"; then
    echo "ELF-D12-ДЕСЯТКОВО-ДІАГНОСТИКА: збірка $name" >&2
    cat "$TMP/$name.build.err" >&2
    cat "$TMP/$name.build.out" >&2
    exit 1
  fi
  test -x "$TMP/$name.elf"
  test ! -s "$TMP/$name.build.err"
  grep -Fq 'опкод-add=01d8' "$TMP/$name.build.out"
  grep -Fq 'зсув-у-файлі=130' "$TMP/$name.build.out"
  timeout 10s "$TMP/$name.elf" >"$TMP/$name.stdout"
  cmp "$TMP/w/$name.stdout" "$TMP/$name.stdout"
  PASS=$((PASS+1))
done
test "$PASS" -eq 6

# --- 2. Вимога задачі буквально: stdout == 5 --------------------------
printf '5\n' >"$TMP/wanted-5"
cmp "$TMP/wanted-5" "$TMP/01.stdout"
[ "$(cat "$TMP/01.stdout")" = '5' ]

# --- 3. Позитивний свідок: байти add у машинному коді -----------------
HEADER=120
ADD_AT=10
OPCODE_OFF=$((HEADER + ADD_AT))
od -An -tx1 -j "$OPCODE_OFF" -N 2 "$TMP/01.elf" >"$TMP/opcode.hex"
[ "$(tr -d ' \n' <"$TMP/opcode.hex")" = '01d8' ]

# Операнди — 2 і 3, а не сума: mov eax,2; mov ebx,3 перед add.
od -An -tx1 -j "$HEADER" -N 10 "$TMP/01.elf" >"$TMP/operands.hex"
[ "$(tr -d ' \n' <"$TMP/operands.hex")" = 'b802000000bb03000000' ]

# Той самий доказ очима дизасемблера, якщо він є в образі.
if command -v objdump >/dev/null; then
  tail -c +$((HEADER + 1)) "$TMP/01.elf" >"$TMP/kod.bin"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/kod.bin" >"$TMP/kod.dis"
  grep -Eiq 'add[[:space:]]+eax,ebx' "$TMP/kod.dis"
  grep -Eiq 'mov[[:space:]]+eax,0x2' "$TMP/kod.dis"
fi

# --- 4. Негативний свідок: зіпсований опкод add ----------------------
NEGW=0
corrupt() {  # $1 — ім'я, $2 — шістнадцяткові байти опкоду
  local name="$1" hex="$2"
  cp "$TMP/01.elf" "$TMP/$name.elf"
  chmod +x "$TMP/$name.elf"
  printf "\\x${hex:0:2}\\x${hex:2:2}" |
    dd of="$TMP/$name.elf" bs=1 seek="$OPCODE_OFF" conv=notrunc status=none
  od -An -tx1 -j "$OPCODE_OFF" -N 2 "$TMP/$name.elf" >"$TMP/$name.hex"
  [ "$(tr -d ' \n' <"$TMP/$name.hex")" = "$hex" ]
  timeout 10s "$TMP/$name.elf" >"$TMP/$name.stdout"
  if cmp -s "$TMP/wanted-5" "$TMP/$name.stdout"; then
    echo "ELF-D12-ДЕСЯТКОВО-ПОМИЛКА: зіпсований опкод $hex досі дає 5" >&2
    exit 1
  fi
  NEGW=$((NEGW+1))
}
# 01 D8 (add eax,ebx) → 29 D8 (sub eax,ebx): 2-3 = -1, а не 5.
corrupt zipsub 29d8
[ "$(cat "$TMP/zipsub.stdout")" = '-1' ]
# 01 D8 → 90 90 (nop nop): сума не виконується, лишається 2.
corrupt zipnop 9090
[ "$(cat "$TMP/zipnop.stdout")" = '2' ]
test "$NEGW" -eq 2

# --- 5. Відмови: хибна форма і D12→D24 -------------------------------
NEGAD=0
reject() {  # $1 — текст програми, $2 — очікуваний код
  local prog="$1" want="$2" target="$TMP/vidmova-$NEGAD.elf"
  if timeout 30s "$CLI" --додати-десятково "$prog" "$target" \
      >"$TMP/vidmova.stdout" 2>"$TMP/vidmova.stderr"; then
    RC=0
  else
    RC=$?
  fi
  [ "$RC" -eq "$want" ]
  test ! -e "$target"
  test ! -s "$TMP/vidmova.stdout"
  grep -Fq 'ELF-D12-ДЕСЯТКОВО-ВІДМОВА' "$TMP/vidmova.stderr"
  NEGAD=$((NEGAD+1))
}
for name in n01 n02 n03 n04 n05 n06 n07 n08 n09; do
  reject "$(cat "$TMP/w/$name.prohrama")" 2
done
for name in o01 o02; do
  reject "$(cat "$TMP/w/$name.prohrama")" 2
  grep -Fq 'D24' "$TMP/vidmova.stderr"
done
# Англійська голова не є прихованим синонімом — відмова названа.
reject '(add 2 3)' 2
test "$NEGAD" -eq 12

# --- 6. No-clobber: наявний ELF не переписується ---------------------
cp "$TMP/01.elf" "$TMP/01.zrazok"
if timeout 30s "$CLI" --додати-десятково "$(cat "$TMP/w/01.prohrama")" \
    "$TMP/01.elf" >"$TMP/clobber.out" 2>"$TMP/clobber.err"; then
  RC=0
else
  RC=$?
fi
[ "$RC" -ne 0 ]
test ! -s "$TMP/clobber.out"
cmp "$TMP/01.zrazok" "$TMP/01.elf"
timeout 10s "$TMP/01.elf" >"$TMP/01.recheck"
cmp "$TMP/wanted-5" "$TMP/01.recheck"

echo "ELF-D12-ДЕСЯТКОВО-ГАРАЗД машинне-додавання=$PASS" \
  "опкод-add=01d8 зсув=$OPCODE_OFF негативних-свідків=$NEGW" \
  "відмов=$NEGAD stdout=5"
