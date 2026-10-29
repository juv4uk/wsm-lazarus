#!/usr/bin/env bash
# G6.86 — повна фізична D5:01000(D12) форма -> verified WideIR -> ELF64.
# НІЯКИХ додаткових мовних законів, не підмінювати D1 host boolean.
set -euo pipefail
trap 'echo "ШИРОКИЙ-Д5-НУЛЬ-ЗБІЙ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ШИРОКИЙ-Д5-НУЛЬ-БЛОК: Linux x86-64' >&2; exit 127; }
# Уся ідентичність D5 і допущений машинний шлях тільки pinned.
grep -Fq '(01000 (ук нуль?) (укр нуль?)' external/sens/lib/domains/d5.lisp
git -C external/sens show HEAD:lib/machine/profile/current-domain-x86-64.lisp |
  grep -Fq 'CMP+SETE+MOVZX / точний внутрішній біт цілого числа'
for tool in fpc cmp readelf objdump timeout git awk grep dd; do
  command -v "$tool" >/dev/null || { echo "НЕМАЄ ІНСТРУМЕНТА: $tool" >&2; exit 127; }
done
UNIT="$ROOT/build/m0.2/irwidezero/units"
BIN="$ROOT/build/m0.2/irwidezero/bin"
mkdir -p "$UNIT" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
for pair in \
  'scripts/test-irwidezero.pas test-irwidezero' \
  'src/senswidezeroelf.lpr senswidezeroelf' \
  'src/sensd12zeroelf.lpr sensd12zeroelf'; do
  read -r source name <<<"$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNIT" -FE"$BIN" "-o$name" "$ROOT/$source"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/physical"
timeout 30s "$BIN/test-irwidezero" "$TMP/physical"
test -s "$TMP/physical/cases.tsv"
PASS=0
forcheck() {
  local label="$1" decimal="$2" bit="$3"
  local whole="$TMP/physical/$label.sens"
  local atomic="$TMP/physical/$label.atom.sens"
  local elf="$TMP/$label.elf"
  timeout 12s "$BIN/senswidezeroelf" --скомпілювати-D5-нуль \
    "$whole" "$elf" >"$TMP/$label.build.stdout" 2>"$TMP/$label.build.stderr"
  test ! -s "$TMP/$label.build.stderr"
  grep -Fq 'machine=TEST_SETE_MOVZX output=D1' "$TMP/$label.build.stdout"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.instructions" bs=1 skip=120 count=78 status=none
  objdump -D -b binary -m i386:x86-64 "$TMP/$label.instructions" >"$TMP/$label.dis"
  grep -Eiq 'test.*%eax' "$TMP/$label.dis"
  grep -Eiq 'sete' "$TMP/$label.dis"
  grep -Eiq 'movz[bw]' "$TMP/$label.dis"
  # Окремо фізичне виконання, а не лише disassembler на офсеті.
  timeout 5s "$elf" >"$TMP/$label.result.sens"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.result.sens"
  # Найсильніший proof повторного використання перевіреного backend:
  # БАЙТОВО той самий ELF, що вже злитий для одноатомного D12.
  timeout 12s "$BIN/sensd12zeroelf" --нуль-D12 \
    "$atomic" "$TMP/$label.old.elf" >/dev/null
  cmp "$elf" "$TMP/$label.old.elf"
  timeout 12s "$BIN/senswidezeroelf" --скомпілювати-D5-нуль \
    "$whole" "$TMP/$label.again.elf" >/dev/null
  cmp "$elf" "$TMP/$label.again.elf"
  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = \
      1f1bf676eeac605e065035d9dd2adaae807f1788
    printf '(нуль? %s)\n' "$decimal" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.stderr"
    test ! -s "$TMP/$label.oracle.stderr"
    printf '%s\n' "$bit" >"$TMP/$label.expected.oracle"
    # Pinned D5:01000 у фактичному REPL повертає рівно D1:1/0.
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
  fi
  PASS=$((PASS+1))
}
while IFS=$'\t' read -r label decimal bit; do
  forcheck "$label" "$decimal" "$bit"
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 10

NEG=0
reject() {
  local destination="$TMP/rejected-$NEG.elf"
  if timeout 12s "$BIN/senswidezeroelf" "$@" "$destination" \
     >"$TMP/partial.stdout" 2>"$TMP/negative.stderr"; then
    echo "ШИРОКИЙ-Д5-НУЛЬ-ПОМИЛКА: допущений негатив $NEG" >&2; exit 1
  fi
  test ! -e "$destination"
  test ! -s "$TMP/partial.stdout"
  grep -Fq 'ЕЛЬФ-Д5-НУЛЬ-ВІДМОВА:' "$TMP/negative.stderr"
  NEG=$((NEG+1))
}
MODE=--скомпілювати-D5-нуль
for invalid in other-head other-domain D1-argument D3-empty D7-argument \
  D24-argument missing-argument extra-argument nested-argument two-roots \
  dot-pair unclosed bare-atom bad-t5m empty fake; do
  if [[ "$invalid" = fake ]]; then
    reject "$MODE" "$TMP/physical/fake.lisp"
  else
    reject "$MODE" "$TMP/physical/$invalid.sens"
  fi
done
reject "$MODE" "$TMP/physical/відсутній.sens"
reject --вигаданий "$TMP/physical/01.sens"
test "$NEG" -eq 18

# No clobber: зайнята ціль незмінна; після відмови звичайний код працює.
cp "$TMP/01.elf" "$TMP/зайнятий.elf"
if timeout 12s "$BIN/senswidezeroelf" "$MODE" \
    "$TMP/physical/02.sens" "$TMP/зайнятий.elf" \
    >"$TMP/occupied.stdout" 2>"$TMP/occupied.stderr"; then
  echo 'ШИРОКИЙ-Д5-НУЛЬ-ПОМИЛКА: перезаписано існуючий ELF' >&2; exit 1
fi
test ! -s "$TMP/occupied.stdout"
cmp "$TMP/01.elf" "$TMP/зайнятий.elf"
timeout 12s "$BIN/senswidezeroelf" "$MODE" "$TMP/physical/01.sens" \
  "$TMP/recovery.elf" >/dev/null
timeout 5s "$TMP/recovery.elf" >"$TMP/recovery.sens"
cmp "$TMP/physical/01.expected.sens" "$TMP/recovery.sens"
echo "ШИРОКИЙ-Д5-НУЛЬ-ГАРАЗД ELF=$PASS негативів=$NEG byte-identical=попередній-backend pinned-D5=так енергія=НЕ-ВИМІРЯНО"
