#!/usr/bin/env bash
# Active Lazarus gate: SENS exact-domain mechanism, without legacy SID8 authority.
# This is NOT a claim of full Core4 execution parity; the evaluator is being migrated.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
UNIT_DIR="$BUILD_DIR/test-units"
BIN_DIR="$BUILD_DIR/bin"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-lcl.sh"

if ! command -v "$FPC_BIN" >/dev/null 2>&1; then
  echo "DOMAIN-FAIL missing Free Pascal compiler: $FPC_BIN" >&2
  exit 127
fi

# Fail closed if deprecated SID8 implementation becomes reachable from the new domain unit.
if grep -nE 'TSid8|wsm\.historical|wsm\.registry|SID8' "$ROOT/src/wsm.domain.pas"; then
  echo "DOMAIN-FAIL legacy identity dependency" >&2
  exit 1
fi

"$ROOT/scripts/build.sh"
mkdir -p "$UNIT_DIR" "$BIN_DIR"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" \
  -FE"$BIN_DIR" -otest-domain "$ROOT/scripts/test-domain.pas"
(cd "$ROOT" && "$BIN_DIR/test-domain")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bind "$ROOT/scripts/test-bind.pas"
(cd "$ROOT" && "$BIN_DIR/test-bind")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bindindex "$ROOT/scripts/test-bindindex.pas"
(cd "$ROOT" && "$BIN_DIR/test-bindindex")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bindtree "$ROOT/scripts/test-bindtree.pas"
(cd "$ROOT" && "$BIN_DIR/test-bindtree")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bindatoms "$ROOT/scripts/test-bindatoms.pas"
(cd "$ROOT" && "$BIN_DIR/test-bindatoms")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-binarybind "$ROOT/scripts/test-binarybind.pas"
(cd "$ROOT" && "$BIN_DIR/test-binarybind")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-binarylocbind "$ROOT/scripts/test-binarylocbind.pas"
(cd "$ROOT" && "$BIN_DIR/test-binarylocbind")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-binarytree "$ROOT/scripts/test-binarytree.pas"
(cd "$ROOT" && "$BIN_DIR/test-binarytree")
"$ROOT/scripts/test-bind-cli.sh"
"$ROOT/scripts/test-compiler.sh"
# G6.203: незалежний дешевий SIR1-тест у вже активному FPC job.
bash "$ROOT/scripts/test-sir1-inspect-atomic.sh"
# G6.210: 10 чинних physical D12→ELF golden + атомарний x64 RIP-fixup.
# Той самий FPC runner, без нового workflow/apt і без SENS oracle підміни.
mkdir -p "$BUILD_DIR/x64rip-units"
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$BUILD_DIR/x64rip-units" \
  -FE"$BIN_DIR" -otest-x64zero-golden "$ROOT/scripts/test-x64zero-golden.pas"
HEAPTRC="log=$BUILD_DIR/x64rip-heap.log" \
  timeout 20s "$BIN_DIR/test-x64zero-golden" > "$BUILD_DIR/x64rip.out"
grep -Fq 'X64-D12-ZERO-GOLDEN-OK elf=10 negative=5 rip=exact recovery=1 rip-budget=2' \
  "$BUILD_DIR/x64rip.out"
grep -Fq '0 unfreed memory blocks' "$BUILD_DIR/x64rip-heap.log"
# Один наявний FPC PR-gate: включає 60+20 механічних перевірок
# native evaluator, без додаткового workflow/apt/важких мов.
timeout 180s bash "$ROOT/scripts/test-nativeeval.sh"
# G6.202: той самий FPC PR-gate перевіряє одноразовий verified WideIR.
# Фізичний T5M→D1 ELF64 та негативи Lower(nil)/reentry, без нового FPC job.
timeout 180s bash "$ROOT/scripts/test-widecontext-once.sh"
# G6: перевірка фізичних байтів pinned D1–D10 + Contract 12 у
# файловому T5M→WideIR→ELF64, включно із refs/replace та recovery.
# Єдиний уже встановлений FPC: без додаткового apt/workflow чи Rust.
timeout 180s bash "$ROOT/scripts/test-widefront-ide-cwd.sh"
# G6: два машинні D6 «модуль» ELF з D12/D24 T5M та 4 фізичні
# негативи sys_write, у цьому самому FPC job без нового workflow/apt.
timeout 180s bash "$ROOT/scripts/test-elfd12abs-write.sh"
# G6.219: один існуючий FPC PR-runner, справжні фізичні D12→D1 ELF64
# з Linux write(1,rsp,1) позитивами, -EBADF/-ENOSPC та recovery.
# Не додаємо workflow, Rust/Zig або нове встановлення компілятора.
# Чому лише повний sys_write дає успішний статус машини?
# Чому host exit(2) не є SENS D1?
# Хто перевіряє фізичний D12/D1 допуск до machine emission?
# Який golden доводить незмінність TEST/SETE/MOVZX?
timeout 180s bash "$ROOT/scripts/test-elfd12zero.sh"
echo "LAZARUS-DOMAIN-GATE-OK scope=exact-domain-and-headless-build core4-execution=not-yet-verified"
