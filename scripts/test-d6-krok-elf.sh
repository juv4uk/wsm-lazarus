#!/usr/bin/env bash
# G6.81 — машинний x86-64 ADD для pinned D6:001110 над D12.
# Базовий gate FPC/ELF та додатковий pinned SENS REPL.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
trap 'echo "D6-КРОК-ПРОВАЛ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
for cmd in git timeout fpc readelf objdump cmp mktemp; do
  command -v "$cmd" >/dev/null || { echo "D6-КРОК-БЛОК: потрібен $cmd" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D6-КРОК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
./scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(001110 (ук додати-1) (укр додати-1)' external/sens/lib/domains/d6.lisp
grep -Fq '(домен-шостий додати-1 fast-path "ADD /' external/sens/lib/machine/profile/current-domain-x86-64.lisp
grep -Fq '(first-domain . D12)' external/sens/contracts/language-contract-12.lisp
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
FPC_BIN=$(printenv FPC || printf 'fpc')
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd6krokelf "$ROOT/src/sensd6krokelf.lpr" >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2; exit 1;
  }
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-d6-krok-elf "$ROOT/scripts/test-d6-krok-elf.pas" >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2; exit 1;
  }
timeout 20s "$TMP/bin/test-d6-krok-elf" "$TMP"
CLI="$TMP/bin/sensd6krokelf"
test -x "$CLI"
PASS=0
for row in '01:-2048:-2047' '02:-1024:-1023' '03:-2:-1' '04:-1:0' \
           '05:0:1' '06:1:2' '07:1023:1024' '08:2046:2047'; do
  IFS=: read -r tag number wanted <<<"$row"
  timeout 12s "$CLI" --додати-1-D12 "$TMP/$tag.sens" "$TMP/$tag.elf" \
    >"$TMP/$tag.stdout" 2>"$TMP/$tag.stderr"
  test ! -s "$TMP/$tag.stderr"
  grep -Fq 'D6-001110-AOT-ELF64' "$TMP/$tag.stdout"
  test -x "$TMP/$tag.elf"
  readelf -h "$TMP/$tag.elf" >"$TMP/$tag.header"
  grep -Eq 'Type:.*DYN' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  timeout 5s "$TMP/$tag.elf" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.exec.err"
  test ! -s "$TMP/$tag.exec.err"
  cmp "$TMP/$tag.actual.sens" "$TMP/$tag.expected.sens"
  test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
  PASS=$((PASS+1))
done
test "$PASS" -eq 8
# Перевірка справжньої машинної інструкції (не літералу суми).
tail -c +121 "$TMP/06.elf" >"$TMP/код-та-дані.bin"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/код-та-дані.bin" >"$TMP/машинні-інструкції.txt"
grep -Eiq 'add[[:space:]]+eax,' "$TMP/машинні-інструкції.txt"

REJECTED=0
reject() {
  local name="$1"
  shift
  local dest="$TMP/відмова-$name.elf" rc=0
  timeout 12s "$CLI" "$@" "$dest" >"$TMP/reject.stdout" 2>"$TMP/reject.stderr" || rc=$?
  test "$rc" -eq 2 && test ! -e "$dest" && test ! -L "$dest"
  test ! -s "$TMP/reject.stdout"
  grep -Fq 'ВІДМОВА:' "$TMP/reject.stderr" || {
    # Host locale FPC може відобразити UTF-8 діагностику як ?,
    # але фактична відмова та відсутність output обов'язкові.
    test -s "$TMP/reject.stderr"
  }
  REJECTED=$((REJECTED+1))
}
cp "$TMP/06.sens" "$TMP/fake.lisp"
reject переповнення --додати-1-D12 "$TMP/overflow.sens"
reject ширина-d24 --додати-1-D12 "$TMP/bad-d24.sens"
reject ширина-d1 --додати-1-D12 "$TMP/bad-d1.sens"
reject дані-d7 --додати-1-D12 "$TMP/bad-d7.sens"
reject пошкоджено --додати-1-D12 "$TMP/bad-t5m.sens"
reject порожній --додати-1-D12 "$TMP/empty.sens"
reject текст --додати-1-D12 "$TMP/fake.lisp"
reject відсутній --додати-1-D12 "$TMP/does-not-exist.sens"
reject невідомий-режим --інша-дія "$TMP/06.sens"
test "$REJECTED" -eq 9
# Захист уже існуючого файла та незмінність цілі.
cp "$TMP/06.elf" "$TMP/existing.elf"
rc=0
timeout 12s "$CLI" --додати-1-D12 "$TMP/06.sens" "$TMP/existing.elf" \
  >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/existing.elf" "$TMP/06.elf"

# Незалежний pinned SENS REPL у повній людській проєкції «укр».
# Якщо upstream D6 не виконується — CI буде червоний, а не фальшивий parity.
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  ORACLE_BIN=$(printenv SENS_ORACLE_BIN)
  test -x "$ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  MATCHES=0
  for row in '01:-2048:-2047' '02:-1024:-1023' '03:-2:-1' '04:-1:0' \
             '05:0:1' '06:1:2' '07:1023:1024' '08:2046:2047'; do
    IFS=: read -r tag number wanted <<<"$row"
    printf '(додати-1 %s)\n' "$number" >"$TMP/$tag.lisp"
    timeout 40s "$ORACLE_BIN" "$TMP/$tag.lisp" \
      >"$TMP/$tag.oracle" 2>"$TMP/$tag.oracle.err" || {
        echo "D6-КРОК-ORACLE-BLOCK форма=$tag" >&2
        cat "$TMP/$tag.oracle.err" >&2
        exit 1
      }
    test ! -s "$TMP/$tag.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$tag.wanted"
    cmp "$TMP/$tag.wanted" "$TMP/$tag.oracle"
    MATCHES=$((MATCHES+1))
  done
  test "$MATCHES" -eq "$PASS"
  echo "D6-КРОК-НЕЗАЛЕЖНИЙ-SENS-ГАРАЗД фізичних=$PASS SENS=$MATCHES pin=$PIN"
fi
echo "D6-КРОК-ELF-ГАРАЗД checked-FPC=так x86-ADD=$PASS T5M=$PASS негативи=$REJECTED energy=НЕ-ВИМІРЯНО"
# Input .sens — фізичні D12 байти; EXE — host ELF64, не SENS.
# 1) Чому grep машинного ADD не заміняє SENS oracle?
# 2) Чому переповнення відхилено до публікації?
# 3) Чому tag — host ID, а не мова?
# 4) Чому джоулі не можна вивести зі статичної інструкції?