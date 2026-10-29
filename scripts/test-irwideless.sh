#!/usr/bin/env bash
# G6.91 — ціла фізична D2/T5M D5:11010(W12,W12), verified WideIR,
# native Linux ELF64 CMP/SETL, незалежний pinned REPL SENS.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
on_error() {
  local rc=$?
  echo "ШИРОКИЙ-D5-МЕНШЕ-ПОМИЛКА: рядок=$1 статус=$rc" >&2
  for file in "$TMP"/bad.stderr "$TMP"/*.compile.stderr \
              "$TMP"/*.oracle.stderr "$TMP"/generator.stderr; do
    if [[ -f "$file" ]]; then
      echo "--- $file ---" >&2
      tail -n 8 "$file" >&2
    fi
  done
  exit "$rc"
}
trap 'on_error "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in fpc git cmp timeout readelf objdump dd awk grep; do
  command -v "$tool" >/dev/null
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(11010 (ук менше?) (укр менше?)' external/sens/lib/domains/d5.lisp
# Sparse pinned working tree: exact git object rather than a copied law.
git -C external/sens show HEAD:lib/machine/profile/current-domain-x86-64.lisp |
  grep -Fq 'CMP+SETL+MOVZX / внутрішній біт'
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/senswidemenelf.lpr senswidemenelf' \
  'src/sensd12mensheelf.lpr sensd12mensheelf' \
  'scripts/test-irwideless.pas test-irwideless'; do
  read -r source binary <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" "$ROOT/$source"
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwideless" "$TMP/physical" \
  >"$TMP/generator.stdout" 2>"$TMP/generator.stderr"
grep -Fq 'G6.91-WIDE-LESS-FIXTURES=18' "$TMP/generator.stdout"
grep -Fq '0 unfreed memory blocks' "$TMP/generator.stderr"
test -s "$TMP/physical/cases.tsv"
PASS=0
while IFS=$'\t' read -r label left right bit; do
  test -n "$label"
  elf="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswidemenelf" --скомпілювати-D5-менше-D12 \
    "$TMP/physical/$label.sens" "$elf" \
    >"$TMP/$label.compile.stdout" 2>"$TMP/$label.compile.stderr"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.compile.stderr"
  grep -Fq 'machine=CMP/SETL/MOVZX stdout=T5M-D1' "$TMP/$label.compile.stdout"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.code" bs=1 skip=120 count=80 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'setl[[:space:]]+al' "$TMP/$label.dis"
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$label.dis"
  timeout 5s "$elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"

  # Verified earlier backend for two separate D12 atoms must emit
  # precisely identical machine image, not a duplicate custom emitter.
  timeout 20s "$TMP/bin/sensd12mensheelf" --менше-D12 \
    "$TMP/physical/$label-l.sens" "$TMP/physical/$label-r.sens" \
    "$TMP/$label.previous.elf" >/dev/null 2>"$TMP/$label.old.stderr"
  cmp "$elf" "$TMP/$label.previous.elf"
  timeout 20s "$TMP/bin/senswidemenelf" --скомпілювати-D5-менше-D12 \
    "$TMP/physical/$label.sens" "$TMP/$label.again.elf" \
    >/dev/null 2>"$TMP/$label.again.stderr"
  cmp "$elf" "$TMP/$label.again.elf"

  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    # Only full Ukrainian human projection, not canonical source.
    printf '(менше? %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.stderr"
    test ! -s "$TMP/$label.oracle.stderr"
    printf '%s\n' "$bit" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 18

NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf" rc=0
  timeout 15s "$TMP/bin/senswidemenelf" "$@" "$target" \
    >"$TMP/bad.stdout" 2>"$TMP/bad.stderr" || rc=$?
  test "$rc" -eq 2 || {
    echo "ШИРОКИЙ-D5-МЕНШЕ: невірний статус відмови $rc номер=$NEG" >&2
    exit 1
  }
  test ! -s "$TMP/bad.stdout"
  test ! -e "$target" && test ! -L "$target"
  grep -Fq 'ЕЛФ-D5-ШИРОКЕ-МЕНШЕ-ВІДМОВА:' "$TMP/bad.stderr"
  grep -Fq '0 unfreed memory blocks' "$TMP/bad.stderr"
  NEG=$((NEG+1))
}
MODE=--скомпілювати-D5-менше-D12
for invalid in other-head other-d5 other-d6 bad-d1-left bad-d1-right \
  bad-d7 bad-d24 head-d7 missing-left missing-right extra-right \
  nested-right two-roots dotted-pair wrong-root unclosed bad-byte empty; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/missing.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$NEG" -eq 21
cp "$TMP/01.elf" "$TMP/зайнятий.elf"
rc=0
timeout 20s "$TMP/bin/senswidemenelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/зайнятий.elf" \
  >"$TMP/occupied.stdout" 2>"$TMP/occupied.stderr" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/occupied.stdout"
cmp "$TMP/01.elf" "$TMP/зайнятий.elf"
timeout 20s "$TMP/bin/senswidemenelf" "$MODE" \
  "$TMP/physical/01.sens" "$TMP/recovery.elf" >/dev/null
timeout 5s "$TMP/recovery.elf" >"$TMP/recovery.sens"
cmp "$TMP/physical/01.expected.sens" "$TMP/recovery.sens"
echo "ШИРОКИЙ-D5-МЕНШЕ-ГАРАЗД ELF=$PASS негативів=$NEG байтовий-старий-backend=так машина=CMP_SETL_MOVZX витоки=0 енергія=НЕ-ВИМІРЯНА"
