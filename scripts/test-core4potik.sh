#!/usr/bin/env bash
# G4.48 — реальне виконання canonical Core4 T5M з raw stdin до stdout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout cmp python3 grep mktemp; do
  command -v "$tool" >/dev/null || { echo "CORE4-ПОТІК-БЛОКЕР: немає $tool" >&2; exit 127; }
done
./scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"
FPC_BIN=$(printenv FPC || echo fpc)
for program in src/senscore4potik.lpr scripts/test-core4multiroot.pas scripts/test-core4session.pas src/senst5m.lpr; do
  case "$program" in
    src/senscore4potik.lpr) name=senscore4potik ;;
    scripts/test-core4multiroot.pas) name=test-core4multiroot ;;
    scripts/test-core4session.pas) name=test-core4session ;;
    *) name=senst5m ;;
  esac
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" -o"$name" "$ROOT/$program" \
    >"$TMP/build-$name.log" 2>&1 || {
      cat "$TMP/build-$name.log" >&2; exit 1;
    }
done
if ! timeout 40s "$TMP/bin/test-core4multiroot" "$ROOT" "$TMP" \
  >"$TMP/generated.out" 2>"$TMP/generated.err"; then
  cat "$TMP/generated.err" >&2; exit 1
fi
grep -Fq 'CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД' "$TMP/generated.out"
grep -Fq '0 unfreed memory blocks' "$TMP/generated.err"
timeout 40s "$TMP/bin/test-core4session" "$ROOT" "$TMP" \
  >"$TMP/session-generated.out" 2>"$TMP/session-generated.err"
grep -Fq 'CORE4-СЕАНС-ФІКСТУРИ-ГАРАЗД' "$TMP/session-generated.out"
grep -Fq '0 unfreed memory blocks' "$TMP/session-generated.err"
printf '1\n' >"$TMP/one.words"
timeout 20s "$TMP/bin/senst5m" --пакувати-слова "$TMP/one.words" \
  >"$TMP/one.sens"
CLI="$TMP/bin/senscore4potik"
ok=0
for pair in '01-tak:one' 'good:expected' 'large:large-expected' 'mixed:mixed-expected'; do
  IFS=: read -r from want <<< "$pair"
  timeout 30s "$CLI" --виконати-потік "$ROOT" \
    <"$TMP/$from.sens" >"$TMP/$from.result.sens" 2>"$TMP/$from.err"
  cmp "$TMP/$want.sens" "$TMP/$from.result.sens"
  grep -Fq '0 unfreed memory blocks' "$TMP/$from.err"
  ok=$((ok+1))
done
# Негативні входи не дають навіть першого байта stdout.
: >"$TMP/empty.sens"
python3 - "$TMP/overlimit.sens" "$TMP/late-corrupt.sens" "$TMP/good.sens" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(bytes([255]) * (4 * 1024 * 1024 + 1))
Path(sys.argv[2]).write_bytes(Path(sys.argv[3]).read_bytes() + bytes([255]))
PY
bad=0
reject() {
  local source="$1" needle="$2" rc=0
  timeout 30s "$CLI" --виконати-потік "$ROOT" \
    <"$TMP/$source.sens" >"$TMP/partial.out" 2>"$TMP/rejected.err" || rc=$?
  if [[ "$rc" != 2 ]]; then
    echo "CORE4-ПОТІК-ПРОВАЛ: $source код=$rc" >&2
    cat "$TMP/rejected.err" >&2; exit 1
  fi
  test ! -s "$TMP/partial.out" || {
    echo "CORE4-ПОТІК-ПРОВАЛ: $source видав часткові T5M-байти" >&2; exit 1;
  }
  grep -Fq 'CORE4-ПОТІК-ПОМИЛКА:' "$TMP/rejected.err"
  grep -Fq "$needle" "$TMP/rejected.err"
  grep -Fq '0 unfreed memory blocks' "$TMP/rejected.err"
  bad=$((bad+1))
}
reject empty 'порожній'
reject broken 'T5M'
reject late 'форма=3'
reject late-64 'форма=64'
reject too-many '1..64'
reject late-corrupt 'T5M'
reject overlimit 'обмеження T5M'
rc=0
"$CLI" --невідомо "$ROOT" <"$TMP/good.sens" \
  >"$TMP/wrong.out" 2>"$TMP/wrong.err" || rc=$?
test "$rc" -eq 64
test ! -s "$TMP/wrong.out"
grep -Fq 'Використання:' "$TMP/wrong.err"
timeout 30s "$CLI" --виконати-потік "$ROOT" \
  <"$TMP/good.sens" >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
cmp "$TMP/expected.sens" "$TMP/recovered.sens"
grep -Fq '0 unfreed memory blocks' "$TMP/recovered.err"
echo "CORE4-ПОТІК-ГАРАЗД pinned=12.0 фізичні=1/3/64 змішані-W24=так позитиви=$ok негативи=$bad stdout=T5M-байт-у-байт пізня-відмова=без-байтів"
