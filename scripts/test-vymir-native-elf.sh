#!/usr/bin/env bash
# G6.187: FPC → pinned фізична програма → реальний ELF64 → коректність кожного запуску → час.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc python3 timeout git cmp mktemp chmod; do
  command -v "$tool" >/dev/null || { echo "ВИМІР-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc)); then echo "ВИМІР-ПРОВАЛ код=$rc" >&2; for f in "$TMP"/*.build "$TMP"/*.err; do [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 12 "$f" >&2; }; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in 'scripts/test-irwidefront.pas test-irwidefront' 'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || { cat "$TMP/$name.build" >&2; exit 1; }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
timeout 30s "$TMP/bin/senswidepotikelf" --скомпілювати-фізичний-потік \
  <"$TMP/physical/09.sens" >"$TMP/09.elf" 2>"$TMP/compiler.err"
chmod 700 "$TMP/09.elf"
timeout 5s "$TMP/09.elf" >"$TMP/actual.sens" 2>"$TMP/machine.err"
test ! -s "$TMP/machine.err"
cmp "$TMP/physical/09.expected.sens" "$TMP/actual.sens"
python3 -m py_compile scripts/vymir-native-elf.py
timeout 40s python3 scripts/vymir-native-elf.py \
  --машина "$TMP/09.elf" --очікуване "$TMP/physical/09.expected.sens" \
  --прогрів 2 --пакетів 3 --повторів 4 >"$TMP/report.json" 2>"$TMP/meter.err"
test ! -s "$TMP/meter.err"
python3 - "$TMP/report.json" "$TMP/09.elf" "$TMP/physical/09.expected.sens" <<'PY'
import hashlib, json, pathlib, sys
j = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert j['формат'] == 'SENS-НАТИВНИЙ-ВИМІР-1'
assert j['виконань-перевірено'] == 14
assert j['пакетів'] == 3 and j['повторів-у-пакеті'] == 4
assert len(j['пакети-нс']) == 3 and all(isinstance(x, int) and x > 0 for x in j['пакети-нс'])
assert j['медіана-нс-на-виклик'] > 0
assert j['енергія-статус'] == 'НЕ-ВИМІРЯНО' and j['енергія-джоулі-пакети'] is None
assert j['машина-sha256'] == hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
assert j['еталон-sha256'] == hashlib.sha256(pathlib.Path(sys.argv[3]).read_bytes()).hexdigest()
PY
printf 'хибний-результат' >"$TMP/wrong.sens"
printf '0\n' >"$TMP/rapl-max"
printf '10\n' >"$TMP/rapl-current"
NEG=0
reject() {
  local rc=0
  timeout 15s python3 scripts/vymir-native-elf.py "$@" >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -ne 0
  test ! -s "$TMP/negative.out"
  test -s "$TMP/negative.err"
  NEG=$((NEG+1))
}
reject --машина "$TMP/09.elf" --очікуване "$TMP/wrong.sens" --прогрів 1 --пакетів 1 --повторів 1
reject --машина "$TMP/physical/09.sens" --очікуване "$TMP/physical/09.expected.sens"
reject --машина /bin/false --очікуване "$TMP/physical/09.expected.sens" --прогрів 1
reject --машина "$TMP/missing.elf" --очікуване "$TMP/physical/09.expected.sens"
reject --машина "$TMP/09.elf" --очікуване "$TMP/physical/09.expected.sens" --rapl-енергія "$TMP/rapl-current"
reject --машина "$TMP/09.elf" --очікуване "$TMP/physical/09.expected.sens" --rapl-енергія "$TMP/rapl-current" --rapl-межа "$TMP/rapl-max"
reject --машина "$TMP/09.elf" --очікуване "$TMP/physical/09.expected.sens" --повторів 0
: >"$TMP/empty.sens"
reject --машина "$TMP/09.elf" --очікуване "$TMP/empty.sens"
test "$NEG" -eq 8
echo "НАТИВНИЙ-ВИМІР-ПРОЙДЕНО FPC=2 ELF=1 перевірених-запусків=14 негативів=$NEG RAPL=НЕ-ВИМІРЯНО"
