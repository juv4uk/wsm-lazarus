#!/usr/bin/env bash
# Незалежний S0 McCarthy pin + фізичний T5M -> укр SENS.
# Без пошкодження Core1, без SID8 і без локального реєстру законів.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for cmd in git fpc gcc timeout cmp grep sed mktemp; do
  command -v "$cmd" >/dev/null || { echo "S0-T5M-БЛОК: потрібен $cmd" >&2; exit 127; }
done
timeout 120s bash scripts/check-pin.sh
PIN="$(git -C external/sens rev-parse HEAD)"
GITLINK="$(git ls-tree HEAD external/sens | awk '{print $3}')"
[[ "$PIN" == "$GITLINK" ]] || { echo "S0-T5M-БЛОК: дрейф SENS pin" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Історичний S0-pin походить ТІЛЬКИ з точно pinned Contract12.0,
# а не з HEAD mccarthy-eval (там уже експортувався Rust SENS).
timeout 45s git -C external/sens show "$PIN:contracts/core1-bootstrap-contract.lisp" > "$TMP/s0-contract"
S0_PIN="$(sed -nE 's/.*\(pinned-commit[[:space:]]+\.[[:space:]]+"([0-9a-f]{40})"\).*/\1/p' "$TMP/s0-contract")"
[[ "$S0_PIN" =~ ^[0-9a-f]{40}$ ]] || { echo 'S0-T5M-БЛОК: не знайдено точний S0 pin' >&2; exit 1; }
[[ "$S0_PIN" == '1ae9745b66a1439c1929b0d9038c680567118a58' ]] ||
  { echo "S0-T5M-БЛОК: ревізія S0 змінилася, потрібен новий аудит" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/units"
timeout 120s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenst5mukr "$ROOT/src/senst5mukr.lpr" >"$TMP/fpc.log" 2>&1 ||
    { cat "$TMP/fpc.log" >&2; exit 1; }

for name in smoke-quote smoke-cond; do
  stem="examples/migrated/$name"
  timeout 45s git -C external/sens show "$PIN:$stem.sens" > "$TMP/$name.sens"
  timeout 45s git -C external/sens show "$PIN:$stem.lisp" > "$TMP/$name.expected"
  timeout 30s "$TMP/bin/senst5mukr" "$ROOT" "$TMP/$name.sens" > "$TMP/$name.actual"
  cmp "$TMP/$name.expected" "$TMP/$name.actual"
done

# Fail closed: неканонічний байт, D2-close без open, W24 без
# самовільного числового domain-law, жодного часткового stdout.
printf '\363' > "$TMP/bad-byte.sens"
printf '\065' > "$TMP/bad-d2.sens"
for bad in bad-byte bad-d2; do
  if timeout 30s "$TMP/bin/senst5mukr" "$ROOT" "$TMP/$bad.sens" \
       >"$TMP/$bad.stdout" 2>"$TMP/$bad.err"; then
    echo "S0-T5M-БЛОК: прийнято некоректний $bad" >&2; exit 1
  fi
  test ! -s "$TMP/$bad.stdout"
  grep -Fq 'S0-T5M-УКР-БЛОК' "$TMP/$bad.err"
done
timeout 45s git -C external/sens show "$PIN:tests/semantic/d5-d12-numberp-law.sens" > "$TMP/wide.sens"
if timeout 30s "$TMP/bin/senst5mukr" "$ROOT" "$TMP/wide.sens" \
   >"$TMP/wide.stdout" 2>"$TMP/wide.err"; then
  echo 'S0-T5M-БЛОК: W24 без закону перетворено у .lisp' >&2; exit 1
fi
test ! -s "$TMP/wide.stdout"

# Критична відмінність S0 NIL = LISP-проєкція D1:0; SENS () = D3:000.
timeout 45s git -C external/sens show "$PIN:lib/domains/d1.lisp" > "$TMP/d1"
timeout 45s git -C external/sens show "$PIN:lib/domains/d3.lisp" > "$TMP/d3"
grep -Fq '(0 (ук ні) (укр ні)' "$TMP/d1"
grep -Fq '(LISP NIL)' "$TMP/d1"
grep -Fq '(000 (ук ()) (укр ())' "$TMP/d3"

# Реальне історичне S0 з саме того SHA, що pinned сучасним SENS.
# Повний корпус історичних реалізацій НЕ стає семантичним oracle SENS.
if [[ "${S0_CHECK_HISTORY:-1}" == 1 ]]; then
  mkdir -p "$TMP/s0"
  timeout 20s git -C "$TMP/s0" init -q
  timeout 100s git -C "$TMP/s0" fetch -q --depth 1 \
    https://github.com/juv4uk/mccarthy-eval.git "$S0_PIN"
  timeout 25s git -C "$TMP/s0" checkout -q --detach FETCH_HEAD
  test "$(git -C "$TMP/s0" rev-parse HEAD)" = "$S0_PIN"
  timeout 160s bash "$TMP/s0/tests/historical-core/run.sh" \
    > "$TMP/historical.log" 2>&1 ||
      { cat "$TMP/historical.log" >&2; exit 1; }
  grep -Fq '22 passed, 0 failed' "$TMP/historical.log"
fi

echo "S0-T5M-ГОТОВО pinned-mccarthy=$S0_PIN SENS=$PIN фізичних-пар=2 негативів=3 історичний-корпус=${S0_CHECK_HISTORY:-1}"
