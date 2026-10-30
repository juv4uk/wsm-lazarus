#!/usr/bin/env bash
# G6.151 — один canonical T5M stdin → спільний pinned WideIR → ELF64 stdout.
# Порівнюємо ВЕСЬ бінарний ELF із файловим CLI і виконуємо машинні результати.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git cmp grep readelf chmod python3 mktemp; do
  command -v "$tool" >/dev/null || { echo "ШИРОКИЙ-ПОТІК-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "ШИРОКИЙ-ПОТІК-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo "ШИРОКИЙ-ПОТІК-БЛОК: потрібен незалежний pinned SENS REPL" >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$? file
  if ((rc)); then
    echo "ШИРОКИЙ-ПОТІК-ПРОВАЛ код=$rc" >&2
    for file in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 15 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
heap_ok() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1" || {
      cat "$1" >&2
      return 1
    }
  fi
}
heap_ok "$TMP/generator.err"
MODE=--скомпілювати-фізичний-потік
PASS=0
ORACLE_PASS=0
while IFS=$'\t' read -r label kind a b expected width; do
  test -n "$label"
  source="$TMP/physical/$label.sens"
  stream="$TMP/$label.stream.elf"
  file="$TMP/$label.file.elf"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$source" >"$stream" 2>"$TMP/$label.stream.err"
  heap_ok "$TMP/$label.stream.err"
  test -x "$TMP/bin/senswidefrontelf"
  timeout 25s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$source" "$file" >"$TMP/$label.file.out" 2>"$TMP/$label.file.err"
  heap_ok "$TMP/$label.file.err"
  cmp "$stream" "$file"
  readelf -h "$stream" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  ! readelf -l "$stream" | grep -Eq 'INTERP|DYNAMIC'
  chmod 700 "$stream"
  timeout 5s "$stream" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  if [[ -n "$ORACLE" ]]; then
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/$label.lisp";;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp";;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp";;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/$label.lisp";;
      *) exit 71;;
    esac
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 16; fi

# Один байт на syscall/flush — реальний pipe, не seekable файл.
python3 - "$TMP/bin/senswidepotikelf" "$TMP/physical/09.sens" "$TMP/09.file.elf" <<'PY'
from pathlib import Path
import subprocess
import sys
exe, source, expected = sys.argv[1:]
p = subprocess.Popen([exe, '--скомпілювати-фізичний-потік'],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE)
for value in Path(source).read_bytes():
    p.stdin.write(bytes((value,)))
    p.stdin.flush()
p.stdin.close()
actual = p.stdout.read()
err = p.stderr.read()
rc = p.wait(timeout=30)
assert rc == 0, (rc, err)
assert actual == Path(expected).read_bytes(), (len(actual), err)
assert b'unfreed memory blocks' not in err or b'0 unfreed memory blocks' in err, err
PY

# Fail-closed: жоден pre-admission негатив не може вивести префікс ELF.
NEG=0
reject() {
  local input="$1" rc=0
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$input" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/reject.out"
  grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
  heap_ok "$TMP/reject.err"
  NEG=$((NEG+1))
}
for bad in bad-t5m two-roots unclosed root-atom dotted \
  bad-zero-arity bad-zero-d1 bad-zero-empty bad-less-arity \
  bad-greater-arity bad-abs-arity bad-abs-d3 bad-zero-d7 \
  bad-less-d1 bad-less-d24 bad-abs-d24; do
  reject "$TMP/physical/$bad.sens"
done
: >"$TMP/empty.sens"
printf '(нуль? 0)\n' >"$TMP/text-ukr.lisp"
python3 - "$TMP/overquota.sens" "$TMP/physical/09.sens" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b'0' * 65537)
source = Path(sys.argv[2]).read_bytes()
Path(sys.argv[1] + '.broken').write_bytes(source + b'\xff')
PY
for bad in empty.sens text-ukr.lisp overquota.sens overquota.sens.broken; do
  reject "$TMP/$bad"
done
test "$NEG" -eq 20
RC=0
timeout 10s "$TMP/bin/senswidepotikelf" --вигаданий-режим \
  <"$TMP/physical/01.sens" >"$TMP/wrong.out" 2>"$TMP/wrong.err" || RC=$?
test "$RC" -eq 64
test ! -s "$TMP/wrong.out"
grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/wrong.err"
# Після негативу той самий stdin знову повертає побайтово той самий ELF.
timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
  <"$TMP/physical/09.sens" >"$TMP/recovered.elf" 2>"$TMP/recovered.err"
heap_ok "$TMP/recovered.err"
cmp "$TMP/09.file.elf" "$TMP/recovered.elf"
# Вже допущені фізичні форми компілюємо з чужого cwd (IDE/host).
# Ті ж machine ELF, а не інший text reader чи семантичний маршрут.
mkdir -p "$TMP/foreign-cwd"
FOREIGN_PASS=0
for sample in 01 09 15 16; do
  (
    cd "$TMP/foreign-cwd"
    timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
      --корінь-sens "$ROOT/external/sens" \
      <"$TMP/physical/$sample.sens" \
      >"$TMP/$sample.foreign.elf" 2>"$TMP/$sample.foreign.err"
  )
  heap_ok "$TMP/$sample.foreign.err"
  cmp "$TMP/$sample.file.elf" "$TMP/$sample.foreign.elf"
  chmod 700 "$TMP/$sample.foreign.elf"
  timeout 5s "$TMP/$sample.foreign.elf" >"$TMP/$sample.foreign.actual.sens" \
    2>"$TMP/$sample.foreign.machine.err"
  test ! -s "$TMP/$sample.foreign.machine.err"
  cmp "$TMP/physical/$sample.expected.sens" "$TMP/$sample.foreign.actual.sens"
  FOREIGN_PASS=$((FOREIGN_PASS+1))
done
test "$FOREIGN_PASS" -eq 4

# Усі відмови ще ДО байтової публікації ELF stdout.
FOREIGN_NEG=0
reject_foreign_root() {
  local rc=0
  (
    cd "$TMP/foreign-cwd"
    timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
      --корінь-sens "$1" \
      <"$TMP/physical/09.sens" \
      >"$TMP/foreign-reject.out" 2>"$TMP/foreign-reject.err"
  ) || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/foreign-reject.out"
  grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/foreign-reject.err"
  heap_ok "$TMP/foreign-reject.err"
  FOREIGN_NEG=$((FOREIGN_NEG+1))
}
reject_foreign_root relative/external/sens
reject_foreign_root "$TMP/foreign-cwd"
reject_foreign_root "$TMP/відсутній-корінь"
test "$FOREIGN_NEG" -eq 3
# G6.257: не достатньо правильної мітки HEAD: фактичні байти
# domains D1..D10 та Contract12 мають відповідати pinned Git tree.
# Локальний shared clone використовує НАЯВНІ git-об'єкти, без мережі.
# Всі спроби працюють з чужого cwd; .sens/IR/backend не змінюємо.
timeout 30s git clone --quiet --shared --no-checkout \
  "$ROOT/external/sens" "$TMP/foreign-pin"
timeout 30s git -C "$TMP/foreign-pin" sparse-checkout set --no-cone \
  'contracts/language-contract-12.lisp' 'lib/domains/d*.lisp'
timeout 30s git -C "$TMP/foreign-pin" checkout --quiet --detach "$PIN"
test "$(git -C "$TMP/foreign-pin" rev-parse HEAD)" = "$PIN"
test -s "$TMP/foreign-pin/lib/domains/d5.lisp"
test -s "$TMP/foreign-pin/contracts/language-contract-12.lisp"
# Чистий alternate root компілює той самий результат.
(
  cd "$TMP/foreign-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    --корінь-sens "$TMP/foreign-pin" \
    <"$TMP/physical/09.sens" >"$TMP/pin-clean.elf" \
    2>"$TMP/pin-clean.err"
)
heap_ok "$TMP/pin-clean.err"
cmp "$TMP/09.file.elf" "$TMP/pin-clean.elf"

# G6.261: той самий фізичний pinned-корінь через legacy cwd.
# IDE та legacy CLI не повинні обходити механізм, наявний в explicit.
mkdir -p "$TMP/legacy-cwd/external"
ln -s "$TMP/foreign-pin" "$TMP/legacy-cwd/external/sens"
(
  cd "$TMP/legacy-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$TMP/physical/09.sens" >"$TMP/legacy-clean.elf" \
    2>"$TMP/legacy-clean.err"
)
heap_ok "$TMP/legacy-clean.err"
cmp "$TMP/09.file.elf" "$TMP/legacy-clean.elf"

# Дописаний коментар лишає D5 структурно валідним.
# Індекс з прапором assume-unchanged може приховати зміну від status.
printf '\n; G6.257 фізична підміна pinned D5 із валідною структурою\n' \
  >> "$TMP/foreign-pin/lib/domains/d5.lisp"
git -C "$TMP/foreign-pin" update-index --assume-unchanged lib/domains/d5.lisp
test "$(git -C "$TMP/foreign-pin" rev-parse HEAD)" = "$PIN"
test -z "$(git -C "$TMP/foreign-pin" status --porcelain)"
# Без явного аргументу --корінь-sens правильний Git HEAD НЕ дозволяє
# приховану підміну D5, навіть якщо stdin завеликий: guard ПЕРЕД read.
LEGACY_PIN_RC=0
(
  cd "$TMP/legacy-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$TMP/overquota.sens" >"$TMP/legacy-pin-rejected.elf" \
    2>"$TMP/legacy-pin-rejected.err"
) || LEGACY_PIN_RC=$?
test "$LEGACY_PIN_RC" -eq 2 && test ! -s "$TMP/legacy-pin-rejected.elf"
grep -Fq 'pinned SENS' "$TMP/legacy-pin-rejected.err"
grep -Fq 'Git tree: lib/domains/d5.lisp' "$TMP/legacy-pin-rejected.err"
! grep -Fq 'T5M 65536' "$TMP/legacy-pin-rejected.err"
heap_ok "$TMP/legacy-pin-rejected.err"

PIN_RC=0
(
  cd "$TMP/foreign-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    --корінь-sens "$TMP/foreign-pin" \
    <"$TMP/overquota.sens" >"$TMP/pin-rejected.elf" \
    2>"$TMP/pin-rejected.err"
) || PIN_RC=$?
test "$PIN_RC" -eq 2 && test ! -s "$TMP/pin-rejected.elf"
grep -Fq 'pinned SENS' "$TMP/pin-rejected.err"
grep -Fq 'Git tree: lib/domains/d5.lisp' "$TMP/pin-rejected.err"
! grep -Fq 'фізичний T5M перевищив' "$TMP/pin-rejected.err"
heap_ok "$TMP/pin-rejected.err"
# Після відновлення саме bytes, а не прапора status, ELF знову ідентичний.
git -C "$TMP/foreign-pin" update-index --no-assume-unchanged lib/domains/d5.lisp
timeout 30s git -C "$TMP/foreign-pin" checkout --quiet "$PIN" -- lib/domains/d5.lisp
(
  cd "$TMP/foreign-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    --корінь-sens "$TMP/foreign-pin" \
    <"$TMP/physical/09.sens" >"$TMP/pin-recovered.elf" \
    2>"$TMP/pin-recovered.err"
)
heap_ok "$TMP/pin-recovered.err"
cmp "$TMP/09.file.elf" "$TMP/pin-recovered.elf"
# Відновлений той самий git worktree з legacy cwd не змінює ELF.
(
  cd "$TMP/legacy-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$TMP/physical/09.sens" >"$TMP/legacy-pin-recovered.elf" \
    2>"$TMP/legacy-pin-recovered.err"
)
heap_ok "$TMP/legacy-pin-recovered.err"
cmp "$TMP/09.file.elf" "$TMP/legacy-pin-recovered.elf"
echo 'WIDE-PIPE-LEGACY-PINNED-PASS clean=byte-exact dirty-D5=blocked assume-unchanged=blocked before-stdin=yes stdout=empty recovery=byte-exact'

echo 'WIDE-PIPE-PINNED-PASS head=correct dirty-D5=blocked assume-unchanged=blocked before-stdin=verified stdout=empty recovery=byte-exact energy=NOT-MEASURED'

# Неканонічний T5M не стає прийнятним завдяки явному pinned шляху.
RC=0
(
  cd "$TMP/foreign-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    --корінь-sens "$ROOT/external/sens" \
    <"$TMP/physical/bad-t5m.sens" \
    >"$TMP/foreign-bad.out" 2>"$TMP/foreign-bad.err"
) || RC=$?
test "$RC" -eq 2 && test ! -s "$TMP/foreign-bad.out"
heap_ok "$TMP/foreign-bad.err"
FOREIGN_NEG=$((FOREIGN_NEG+1))

# Без явного кореня з іншого cwd старий режим не вгадує місце SENS.
RC=0
(
  cd "$TMP/foreign-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    <"$TMP/physical/09.sens" >"$TMP/foreign-default.out" \
    2>"$TMP/foreign-default.err"
) || RC=$?
test "$RC" -eq 2 && test ! -s "$TMP/foreign-default.out"
FOREIGN_NEG=$((FOREIGN_NEG+1))

# Відновлення після всіх негативів із тотожним фізичним результатом.
(
  cd "$TMP/foreign-cwd"
  timeout 25s "$TMP/bin/senswidepotikelf" "$MODE" \
    --корінь-sens "$ROOT/external/sens" \
    <"$TMP/physical/09.sens" >"$TMP/foreign-recovered.elf" \
    2>"$TMP/foreign-recovered.err"
)
cmp "$TMP/09.file.elf" "$TMP/foreign-recovered.elf"
heap_ok "$TMP/foreign-recovered.err"
echo "WIDE-PIPE-FOREIGN-OK native=$FOREIGN_PASS negatives=$FOREIGN_NEG byte-identical=yes oracle-in-existing-suite=$ORACLE_PASS energy=NOT-MEASURED"
echo "G6.151-WIDE-PIPE-PASS physical=$PASS identical=$PASS executed=$PASS oracle=$ORACLE_PASS negative=$NEG fragmented=1-byte recovered=yes energy=NOT-MEASURED"
