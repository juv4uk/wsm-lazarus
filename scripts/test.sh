#!/usr/bin/env bash
# Active Lazarus gate: SENS exact-domain mechanism, without legacy SID8 authority.
# This is NOT a claim of full Core4 execution parity; the evaluator is being migrated.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# Анотація для UI: агрегатор падав без жодного слова про те, ЯКИЙ крок зламався,
# а в GitHub видно лише conclusion=failure. Тепер EXIT-пастка називає команду.
# shellcheck source=/dev/null
. "$ROOT/scripts/gh-annotate.sh" 2>/dev/null || true
trap '_rc=$?; if [ "$_rc" -ne 0 ]; then
        echo "DOMAIN-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
        if command -v gh_error >/dev/null 2>&1; then
          gh_error "агрегатор test.sh" "крок упав (код $_rc): $BASH_COMMAND"
        fi
      fi' EXIT

FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
UNIT_DIR="$BUILD_DIR/test-units"
BIN_DIR="$BUILD_DIR/bin"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-stale-pin-hardcode.sh"
"$ROOT/scripts/check-no-lcl.sh"

if ! command -v "$FPC_BIN" >/dev/null 2>&1; then
  echo "DOMAIN-FAIL missing Free Pascal compiler: $FPC_BIN" >&2
  exit 127
fi

# G6.231 — шим бібліотек лінкування FPC (-lc/-ldl).
# У мінімальному контейнері є лише libc.so.6/libdl.so.2, але немає
# development-симлінків libc.so/libdl.so, тому ld.bfd каже «cannot find -lc».
# Хелпер створює шим і дописує -Fl<шим> у ~/.fpc.cfg, який читає кожен
# виклик fpc. Ставимо його ДО першої компіляції (нижче — build.sh).
#
# Збій шиму тут ФАТАЛЬНИЙ і ГУЧНИЙ: якщо хелпер не зміг забезпечити -lc/-ldl,
# то компіляція далі впаде все одно — але мовчазне продовження приховало б
# справжню причину за загальним «DOMAIN-FAIL крок=build.sh». Перевірки це
# не послаблює: жоден тест не вимикається і жоден прапорець не знімається.
if ! bash "$ROOT/scripts/lib-fpc-libs.sh"; then
  echo "DOMAIN-FAIL lib-fpc-libs.sh: не вдалось забезпечити -lc/-ldl (див. FPC-LIBS-FAIL вище)" >&2
  exit 1
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
bash "$ROOT/scripts/test-sir1-inspect-atomic.sh"
mkdir -p "$BUILD_DIR/x64rip-units"
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$BUILD_DIR/x64rip-units" \
  -FE"$BIN_DIR" -otest-x64zero-golden "$ROOT/scripts/test-x64zero-golden.pas"
HEAPTRC="log=$BUILD_DIR/x64rip-heap.log" \
  timeout 20s "$BIN_DIR/test-x64zero-golden" > "$BUILD_DIR/x64rip.out"
grep -Fq 'X64-D12-ZERO-GOLDEN-OK elf=10 negative=5 rip=exact recovery=1 rip-budget=2' \
  "$BUILD_DIR/x64rip.out"
grep -Fq '0 unfreed memory blocks' "$BUILD_DIR/x64rip-heap.log"
timeout 180s bash "$ROOT/scripts/test-nativeeval.sh"
timeout 180s bash "$ROOT/scripts/test-widecontext-once.sh"
timeout 180s bash "$ROOT/scripts/test-widefront-ide-cwd.sh"
timeout 180s bash "$ROOT/scripts/test-elfd12abs-write.sh"
timeout 180s bash "$ROOT/scripts/test-elfd12zero.sh"
echo "LAZARUS-DOMAIN-GATE-OK scope=exact-domain-and-headless-build core4-execution=not-yet-verified"
