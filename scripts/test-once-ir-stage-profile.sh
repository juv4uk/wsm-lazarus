#!/usr/bin/env bash
# G6.188: окреме FPC профілювання механічних етапів; НЕ дублювати #820.
# Готуємо 16 canonical pinned source-backed форм, зберігаємо raw ns у JSON.
# Той самий набір реально виконується на вже наявному native test harness.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'ЕТАПИ-БЛОК: лише Linux x86-64' >&2; exit 127; }
for tool in fpc git timeout python3 mktemp grep cp; do
  command -v "$tool" >/dev/null || {
    echo "ЕТАПИ-БЛОК: немає $tool" >&2; exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "ЕТАПИ-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.out; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 28 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for spec in \
  'scripts/test-irwidefront.pas:test-irwidefront' \
  'scripts/test-once-ir-stage-profile.pas:test-once-ir-stage-profile' \
  'src/senswidesesiiaelf.lpr:senswidesesiiaelf'; do
  IFS=: read -r source name <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
      cat "$TMP/$name.build" "$TMP/$name.err" >&2; exit 1; }
  test -x "$TMP/bin/$name"
done
timeout 60s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
# Важливо: в цьому профілі час НЕ включає збирання FPC та cold startup.
timeout 360s "$TMP/bin/test-once-ir-stage-profile" \
  external/sens "$TMP/physical" >"$TMP/stage.tsv" 2>"$TMP/stage.err" || {
    cat "$TMP/stage.err" >&2; exit 1; }
test ! -s "$TMP/stage.err"
timeout 30s python3 scripts/test-once-ir-stage-profile.py \
  "$TMP/stage.tsv" "$TMP/stages.json" >"$TMP/stages.out"
grep -Fxq 'ЕТАПИ-T5M-WIDEIR-OK distinct=16 rounds=3 samples=48 negatives=2 exact-ir=48 pinned-reloaded=48' "$TMP/stages.out"
test -s "$TMP/stages.json"
# Машинний доказ уже існує у main: повторно застосовуємо його БЕЗ
# дублювання fixture/oracle/бенчмарку PR #820 та без нового emitter.
timeout 580s python3 scripts/test-wide-sesiia-first-snapshot.py \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  >"$TMP/native.out" 2>"$TMP/native.err" || {
    cat "$TMP/native.err" >&2; exit 1; }
grep -Fxq 'ПЕРША-КОМПІЛЯЦІЯ-ПРОЙДЕНО fresh=16 negative=2 elf-executed=16 parity=byte-exact cycles=3 oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/native.out"
cat "$TMP/stages.out"
grep -F 'ПЕРША-КОМПІЛЯЦІЯ-ПРОЙДЕНО' "$TMP/native.out"
if [[ -n "${SENS_ONCE_IR_STAGE_REPORT_DEST:-}" ]]; then
  cp "$TMP/stages.json" "$SENS_ONCE_IR_STAGE_REPORT_DEST"
fi
echo 'ЕТАПИ-МАШИННИЙ-ДОКАЗ-OK FPC=3.2.2 ELF=16 oracle=NOT-CHECKED energy=NOT-MEASURED'
