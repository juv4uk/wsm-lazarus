#!/usr/bin/env bash
# G6.78 — справжній signed D12 CMP/SETG/MOVZX у x86-64 ELF64.
# Українська укр — лише передача незалежному pinned REPL.
# Canonical T5M/бінарна D12 ідентичність не замінюється проєкцією.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д12-БІЛЬШЕ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump python3 git; do
  command -v "$tool" >/dev/null || {
    echo "Д12-БІЛЬШЕ-БЛОК: немає $tool" >&2; exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(first-domain . D12)' external/sens/contracts/language-contract-12.lisp
grep -Fq '(11011 (ук більше?) (укр більше?)' external/sens/lib/domains/d5.lisp
# Sparse materialization НЕ містить машинного профілю: читаємо лише
# первинний Git blob з точно закріпленого SHA, не створюючи тіньовий authority.
timeout 120s git -C external/sens show \
  "$PIN:lib/machine/profile/current-domain-x86-64.lisp" | \
  grep -Fq "(домен-п'ятий більше? proof \"CMP+SETG+MOVZX"
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for p in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$p" ]]; then echo "-- $p" >&2; tail -35 "$p" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixture" "$TMP/свідки"
for row in 'src/sensd12bilsh-elf.lpr sensd12bilsh-elf units-cli' \
           'scripts/test-elfd12bilsh.pas test-elfd12bilsh units-fixture'; do
  read -r path name units <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" \
    "-o$name" "$ROOT/$path" > "$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd12bilsh" "$TMP/свідки" \
  >"$TMP/матриця.tsv" 2>"$TMP/свідки.err"
test "$(wc -l < "$TMP/матриця.tsv")" -eq 12
grep -Fq 'ЕЛФ-Д12-БІЛЬШЕ-СВІДКИ-ГОТОВО пар=12' "$TMP/свідки.err"
COUNT=0
ORACLE=0
while IFS=$'\t' read -r label left right expected; do
  test -n "$label"
  [[ "$expected" == 'ТАК' || "$expected" == 'НІ' ]]
  ELF="$TMP/$label.elf"
  timeout 10s "$TMP/bin/sensd12bilsh-elf" --більше-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" "$ELF" \
    >"$TMP/$label.compile.log" 2>"$TMP/$label.compile.err"
  test ! -s "$TMP/$label.compile.err"
  grep -Fq 'machine=CMP/SETG T5M=D1' "$TMP/$label.compile.log"
  test -x "$ELF"
  readelf -h "$ELF" | grep -Eq 'Type:.*DYN'
  timeout 5s "$ELF" >"$TMP/$label.actual.sens"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/$label.actual.sens"
  # Детермінізм image bytes, включно з канонічною D1 T5M таблицею.
  timeout 10s "$TMP/bin/sensd12bilsh-elf" --більше-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" \
    "$TMP/$label-again.elf" >/dev/null
  cmp "$ELF" "$TMP/$label-again.elf"
  if [[ -v SENS_ORACLE_BIN ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(більше? %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err" || {
        cat "$TMP/$label.oracle.err" >&2; exit 1;
      }
    test ! -s "$TMP/$label.oracle.err"
    python3 - "$TMP/$label.oracle" "$expected" <<'PY'
from pathlib import Path
import sys
actual = Path(sys.argv[1]).read_text(encoding='utf-8').strip()
if actual.startswith('sens[укр]> '):
    actual = actual[len('sens[укр]> '):].strip()
projection = {'1':'ТАК', '0':'НІ', 'ТАК':'ТАК', 'НІ':'НІ',
              '(т а к)':'ТАК', '(н і)':'НІ'}
assert actual in projection, f'невідомий pinned D1 формат: {actual!r}'
assert projection[actual] == sys.argv[2], f'REPL розбіжність: {actual!r}'
PY
    ORACLE=$((ORACLE+1))
  fi
  COUNT=$((COUNT+1))
done < "$TMP/матриця.tsv"
test "$COUNT" -eq 12
if [[ -v SENS_ORACLE_BIN ]]; then test "$ORACLE" -eq 12; fi

# Обов'язковий машинний opcode саме CMP/SETG/MOVZX, не зашита константа.
python3 - "$TMP/03.elf" <<'PY'
import sys
from pathlib import Path
code = Path(sys.argv[1]).read_bytes()[120:]
assert code[:1] == b'\xb8' and code[5:6] == b'\xb9'
assert b'\x39\xc8\x0f\x9f\xc0\x0f\xb6\xc0' in code[:30]
assert code.count(b'\x0f\x05') == 3
PY
dd if="$TMP/03.elf" of="$TMP/instructions" bs=1 skip=120 count=96 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/instructions" >"$TMP/дизасембльовано"
grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/дизасембльовано"
grep -Eiq 'setg[[:space:]]+al' "$TMP/дизасембльовано"
grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/дизасембльовано"
grep -Eiq 'cmp[[:space:]]+rax,0x1' "$TMP/дизасембльовано"
grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/дизасембльовано"

NEG=0
reject() {
  local target="$TMP/відхилено-$NEG.elf"
  if timeout 12s "$TMP/bin/sensd12bilsh-elf" "$@" "$target" \
      >"$TMP/partial.stdout" 2>"$TMP/rejected.err"; then
    echo "Д12-БІЛЬШЕ-ПОМИЛКА: негатив $NEG прийнято" >&2; exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/partial.stdout"
  grep -Fq 'ЕЛФ-Д12-БІЛЬШЕ-ВІДМОВА:' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
BASE="$TMP/свідки/06-l.sens"
OTHER="$TMP/свідки/06-r.sens"
reject --більше-D12 "$TMP/свідки/bad1.sens" "$OTHER"
reject --більше-D12 "$TMP/свідки/bad7.sens" "$OTHER"
reject --більше-D12 "$TMP/свідки/bad24.sens" "$OTHER"
reject --більше-D12 "$TMP/свідки/corrupt.sens" "$OTHER"
reject --більше-D12 "$TMP/свідки/empty.sens" "$OTHER"
cp "$BASE" "$TMP/підробка.lisp"
reject --більше-D12 "$TMP/підробка.lisp" "$OTHER"
reject --більше-D12 "$TMP/відсутній.sens" "$OTHER"
reject --невідомий "$BASE" "$OTHER"
reject --більше-D12 "$BASE" "$TMP/свідки/bad24.sens"
test "$NEG" -eq 9
# Атомарний no-clobber: існуючий ELF не змінюється, stdout порожній.
cp "$TMP/03.elf" "$TMP/зайнятий.elf"
if timeout 12s "$TMP/bin/sensd12bilsh-elf" --більше-D12 \
    "$BASE" "$OTHER" "$TMP/зайнятий.elf" \
    >"$TMP/partial.stdout" 2>"$TMP/rejected.err"; then
  echo 'Д12-БІЛЬШЕ-ПОМИЛКА: перезаписано наявний ELF' >&2; exit 1
fi
cmp "$TMP/03.elf" "$TMP/зайнятий.elf"
test ! -s "$TMP/partial.stdout"
timeout 12s "$TMP/bin/sensd12bilsh-elf" --більше-D12 \
  "$BASE" "$OTHER" "$TMP/після-відмови.elf" > /dev/null
timeout 5s "$TMP/після-відмови.elf" >"$TMP/після-відмови.sens"
cmp "$TMP/свідки/06-expected.sens" "$TMP/після-відмови.sens"
# G6.215: signed D12 «більше?» із реальним машинним D1:0 та D1:1.
# Успіх тільки після повного sys_write(1,stack,1); Linux -EBADF/-ENOSPC
# не повинен маскуватися як SENS-відповідь. Ці host негативи не є oracle.
test -c /dev/full
WRITE_NEG=0
WRITE_RECOVERY=0
# Перевірити всю матрицю фізичних D12 ELF, а не лише дві пари.
while IFS=
  ELF="$TMP/$label.elf"
  test -x "$ELF"
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/$label.closed.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.closed.err"
  WRITE_NEG=$((WRITE_NEG+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/$label.full.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.full.err"
  WRITE_NEG=$((WRITE_NEG+1))

  timeout 5s "$ELF" >"$TMP/$label.recovered.sens" 2>"$TMP/$label.recovered.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/$label.recovered.sens"
  test "$(wc -c < "$TMP/$label.recovered.sens")" -eq 1
  test ! -s "$TMP/$label.recovered.err"
  WRITE_RECOVERY=$((WRITE_RECOVERY+1))
done < "$TMP/матриця.tsv"
test "$WRITE_NEG" -eq 24 && test "$WRITE_RECOVERY" -eq 12
echo "Д12-БІЛЬШЕ-ELF-ГАРАЗД signed-випадків=$COUNT pinned-REPL=$ORACLE негативів=$NEG write-негативів=$WRITE_NEG відновлень=$WRITE_RECOVERY machine=CMP/SETG/MOVZX/CMP/JNE фізичний-D1=так no-clobber=так енергія=НЕ-ВИМІРЯНО"
\t' read -r label left right expected; do
  ELF="$TMP/$label.elf"
  test -x "$ELF"
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/$label.closed.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.closed.err"
  WRITE_NEG=$((WRITE_NEG+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/$label.full.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.full.err"
  WRITE_NEG=$((WRITE_NEG+1))

  timeout 5s "$ELF" >"$TMP/$label.recovered.sens" 2>"$TMP/$label.recovered.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/$label.recovered.sens"
  test "$(wc -c < "$TMP/$label.recovered.sens")" -eq 1
  test ! -s "$TMP/$label.recovered.err"
  WRITE_RECOVERY=$((WRITE_RECOVERY+1))
done
test "$WRITE_NEG" -eq 4 && test "$WRITE_RECOVERY" -eq 2
echo "Д12-БІЛЬШЕ-ELF-ГАРАЗД signed-випадків=$COUNT pinned-REPL=$ORACLE негативів=$NEG write-негативів=$WRITE_NEG відновлень=$WRITE_RECOVERY machine=CMP/SETG/MOVZX/CMP/JNE фізичний-D1=так no-clobber=так енергія=НЕ-ВИМІРЯНО"
