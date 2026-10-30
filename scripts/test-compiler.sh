#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/m0.2"
mkdir -p "$BUILD/units" "$BUILD/bin"
fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$BUILD/units" -FE"$BUILD/bin" -osensc "$ROOT/src/sensc.lpr"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$BUILD/bin/sensc" --compile-ir "$ROOT/external/sens/lib/core4.lisp" "$tmp/one.sir"
"$BUILD/bin/sensc" --compile-ir "$ROOT/external/sens/lib/core4.lisp" "$tmp/two.sir"
cmp "$tmp/one.sir" "$tmp/two.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/one.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/two.sir"
# G6.2: statistics are structural-only and MUST be deterministic.
"$BUILD/bin/sensc" --inspect-ir "$tmp/one.sir" > "$tmp/one.stats"
"$BUILD/bin/sensc" --inspect-ir "$tmp/two.sir" > "$tmp/two.stats"
cmp "$tmp/one.stats" "$tmp/two.stats"
grep -Eq 'tokens=[1-9][0-9]*' "$tmp/one.stats"
grep -Eq 'opens=[1-9][0-9]*' "$tmp/one.stats"
grep -Eq 'payload_bytes=[1-9][0-9]*' "$tmp/one.stats"
grep -Eq 'max_depth=[1-9][0-9]*' "$tmp/one.stats"

# SIR1 fixtures are mechanical corruption tests, not SENS semantic laws.
printf 'SIR1\000\000\000\000\000' > "$tmp/empty-ok.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/empty-ok.sir"
"$BUILD/bin/sensc" --inspect-ir "$tmp/empty-ok.sir" > "$tmp/empty.stats"
test "$(cat "$tmp/empty.stats")" = 'SENSC-SIR1-INSPECT-OK structural-only=1 tokens=1 opens=0 closes=0 atoms=0 strings=0 payload_bytes=0 max_depth=0'
printf 'BIR1\000\000\000\000\000' > "$tmp/bad-magic.sir"
printf 'SIR1' > "$tmp/missing-end.sir"
printf 'SIR1\007\000\000\000\000' > "$tmp/bad-opcode.sir"
printf 'SIR1\001\000\000\000\000\000\000\000\000\000' > "$tmp/unclosed.sir"
printf 'SIR1\002\000\000\000\000\000\000\000\000\000' > "$tmp/extra-close.sir"
printf 'SIR1\003\007\000\000\000ab' > "$tmp/truncated.sir"
printf 'SIR1\004\001\000\000\000x\000\000\000\000\000' > "$tmp/bad-string.sir"
printf 'SIR1\001\001\000\000\000x\000\000\000\000\000' > "$tmp/bad-struct.sir"
printf 'SIR1\000\001\000\000\000x' > "$tmp/bad-end.sir"
cp "$tmp/one.sir" "$tmp/trailing.sir"
printf 'x' >> "$tmp/trailing.sir"
for bad in bad-magic missing-end bad-opcode unclosed extra-close truncated bad-string bad-struct bad-end trailing; do
  if "$BUILD/bin/sensc" --verify-ir "$tmp/$bad.sir"; then
    echo "SENSC-FAIL corrupt SIR1 accepted: $bad" >&2
    exit 1
  fi
  if "$BUILD/bin/sensc" --inspect-ir "$tmp/$bad.sir" > "$tmp/invalid.stats"; then
    echo "SENSC-FAIL corrupt SIR1 inspection accepted: $bad" >&2
    exit 1
  fi
done
printf '(незакрите' > "$tmp/bad.lisp"
if "$BUILD/bin/sensc" --compile-ir "$tmp/bad.lisp" "$tmp/bad.sir"; then
  echo 'SENSC-FAIL malformed source accepted' >&2
  exit 1
fi
test ! -e "$tmp/bad.sir"
echo 'SENSC-IR-TEST-OK deterministic=1 malformed=reject verifier=12-cases inspector=corrupt-reject stats=deterministic'
# G7.1: independent heap-mechanism test; does not confer SENS law authority.
bash "$ROOT/scripts/test-gc.sh"

# G1.2: physical T5M .sens transport test; neither SENS law nor Core4 execution.
fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$BUILD/units" \
  -FE"$BUILD/bin" -otest-t5m "$ROOT/scripts/test-t5m.pas"
(cd "$ROOT" && "$BUILD/bin/test-t5m")
# G5.1 independent session mechanism, not a SENS semantic evaluator.
bash "$ROOT/scripts/test-session.sh"

# G6.168/G6.200: механічні нативні ELF-регресії з одним FPC-встановленням.
# Вхід: фізичні T5M з pinned authority; вихід: машинні ELF і побайтові докази.
# Кожен harness керує власним mktemp та прибирає його під час завершення.
# Це НЕ нові закони SENS і НЕ незалежний REPL-oracle для всіх D3 форм.
# 1. Чому обидва профілі мають запускатися з одного PR FPC runner?
# 2. Чим фізичне виконання ELF відрізняється від паритету SENS REPL?
# 3. Чому ручні окремі workflow не відключені?
# 4. Які негативи захищають malformed T5M та machine stdout?
bash "$ROOT/scripts/test-irwide-d3-elf.sh"
bash "$ROOT/scripts/test-widepotikelf.sh"
# G6.205: зберегти двійковий D5:10110 в одному verified WideIR.
# Той самий FPC PR runner, без другого workflow або незалежної інсталяції.
# Справжні executable T5M stdin/output, негативи й порівняння proof ELF.
bash "$ROOT/scripts/test-mulstream-context.sh"
