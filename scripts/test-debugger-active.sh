#!/usr/bin/env bash
# G7.8 (задача #655) — АКТИВНА частина нативного налагоджувача SENS:
# точка зупину на фізичному вузлі образу ELF і огляд кадру в момент
# зупину. Механічна перевірка, НЕ перевірка законів SENS.
#
# Позитивний свідок: точка на байті $01 $D8 (зсув 120+10 образу
# «(додати 2 3)») справді спрацьовує; у кадрі rax=2, rbx=3; після
# зупину програма дораховує 5 і завершується з кодом 0.
#
# Свідок повторного зупину (обмеження 1 першого зрізу): образ
# «(додати 6 4)» друкує 10, тож цикл видобування цифр виконує ту саму
# інструкцію двічі. Точка на тому зсуві мусить дати stops=2 на ТІЙ
# САМІЙ адресі (same_address=1). Без PTRACE_SINGLESTEP цей свідок
# провалюється з «спрацювала не двічі, а 1» — перевірено.
#
# Свідок кількох точок (обмеження 2): дві точки в одному запуску дають
# три зупини (add один раз, div двічі).
#
# Свідок іншого фізичного образу (обмеження 4): wsm.elfd12loop — інший
# генератор, інші інструкції ($05 imm32, $FF $C9), інші зсуви; три
# ітерації дають шість зупинів.
#
# Негативний свідок: без точки зупину — жодного звернення до ptrace,
# жодного зупину, ті самі байти образу, той самий stdout і код виходу,
# час у межах шуму проти контролю без налагоджувача. Той самий
# негативний свідок є і на образі циклу.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
UNIT_DIR="$ROOT/build/debugger-active/units"
BIN_DIR="$ROOT/build/debugger-active/bin"
mkdir -p "$UNIT_DIR" "$BIN_DIR"

"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-debugger-active "$ROOT/scripts/test-debugger-active.pas"

LOG="$BIN_DIR/debugger-active.log"
(cd "$ROOT" && timeout 180 "$BIN_DIR/test-debugger-active") | tee "$LOG"

# Позитивний свідок.
grep -Fq 'DEBUGGER-ACTIVE-OK' "$LOG"
grep -Fq 'node=image:130' "$LOG"
grep -Fq 'frame=rax2,rbx3' "$LOG"
grep -Fq 'value_after_stop=5' "$LOG"
grep -Fq 'stops=1' "$LOG"
# Свідок повторного зупину: та сама точка, та сама адреса, два зупини.
grep -Fq 'DEBUGGER-REPEAT-OK' "$LOG"
grep -Fq 'stops=2 same_address=1' "$LOG"
grep -Fq 'rax_seq=10,1' "$LOG"
# Свідок кількох точок за один запуск.
grep -Fq 'DEBUGGER-MULTI-OK' "$LOG"
grep -Fq 'stops=3 order=130,176,176' "$LOG"
# Свідок іншого фізичного образу.
grep -Fq 'DEBUGGER-OTHER-NODE-OK' "$LOG"
grep -Fq 'opcodes=05,ffc9 stops=6' "$LOG"
# Огляд ланцюга кадрів: затінення більше не ховає власне значення.
grep -Fq 'DEBUGGER-FRAME-CHAIN-OK' "$LOG"
grep -Fq 'shadowed=29 outer_own=10' "$LOG"
# Негативний свідок.
grep -Fq 'ptrace_when_disabled=0' "$LOG"
grep -Fq 'stops_when_disabled=0' "$LOG"
grep -Fq 'bytes=same' "$LOG"
grep -Fq 'ratio=' "$LOG"
# Негативний свідок на іншому образі.
grep -Fq 'DEBUGGER-OTHER-NEGATIVE-OK' "$LOG"

echo 'DEBAGER-АКТИВНИЙ-ЗБІРКА-ГАРАЗД точка=так повтор=так кілька-точок=так інший-образ=так ланцюг-кадрів=так без-точки=нуль-змін'
