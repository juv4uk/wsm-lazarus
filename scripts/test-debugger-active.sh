#!/usr/bin/env bash
# G7.8 (задача #655) — АКТИВНА частина нативного налагоджувача SENS:
# точка зупину на фізичному вузлі образу ELF і огляд кадру в момент
# зупину. Механічна перевірка, НЕ перевірка законів SENS.
#
# Позитивний свідок: точка на байті $01 $D8 (зсув 120+10 образу
# «(додати 2 3)») справді спрацьовує; у кадрі rax=2, rbx=3; після
# зупину програма дораховує 5 і завершується з кодом 0.
#
# Негативний свідок: без точки зупину — жодного звернення до ptrace,
# жодного зупину, ті самі байти образу, той самий stdout і код виходу,
# час у межах шуму проти контролю без налагоджувача.
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
# Негативний свідок.
grep -Fq 'ptrace_when_disabled=0' "$LOG"
grep -Fq 'stops_when_disabled=0' "$LOG"
grep -Fq 'bytes=same' "$LOG"
grep -Fq 'ratio=' "$LOG"

echo 'DEBAGER-АКТИВНИЙ-ЗБІРКА-ГАРАЗД точка=так кадр=так без-точки=нуль-змін'
