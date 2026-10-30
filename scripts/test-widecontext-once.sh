#!/usr/bin/env bash
# G6 — host VerifiedWideIR lowering рівно один раз, фізичний ELF.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for t in git fpc timeout mktemp cmp readelf grep; do
  command -v "$t" >/dev/null || { echo "WIDECONTEXT-ONCE-BLOCK відсутній $t" >&2;exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'WIDECONTEXT-ONCE-BLOCK потрібен Linux x86-64' >&2;exit 127;
}
timeout 240s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
if [[ -n "${EXPECTED_HEAD_SHA:-}" ]];then
  test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD_SHA" || {
    echo 'WIDECONTEXT-ONCE-BLOCK невідповідний PR HEAD' >&2;exit 1;
  }
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if ((rc));then
    for f in "$TMP"/*.log;do
      [[ ! -f "$f" ]] || { echo "--- $f" >&2;tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'scripts/test-zero-context-fixtures.pas test-zero-context-fixtures' \
  'scripts/test-widecontext-once.pas test-widecontext-once';do
  read -r source executable <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.log" 2>&1 || {
    cat "$TMP/$executable.log" >&2;exit 1;
  }
  test -x "$TMP/bin/$executable"
done
timeout 20s "$TMP/bin/test-zero-context-fixtures" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>&1
grep -Fq 'ZERO-CONTEXT-FIXTURES-OK count=16 negatives=8' "$TMP/fixtures.log"
timeout 90s "$TMP/bin/test-widecontext-once" \
  "$TMP/physical/01.sens" "$TMP/program.elf" \
  >"$TMP/once.log" 2>&1 || {
  cat "$TMP/once.log" >&2;exit 1;
}
grep -Fq 'WIDECONTEXT-ONCE-PASS checks=' "$TMP/once.log"
# ET_DYN може відображатися readelf як "Shared object file" або PIE.
# Перевіряємо машинний тип, а не локалізований опис класифікатора.
readelf -h "$TMP/program.elf" >"$TMP/elf-header.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf-header.log"
chmod 700 "$TMP/program.elf"
timeout 10s "$TMP/program.elf" >"$TMP/result.sens" 2>"$TMP/result.err"
test ! -s "$TMP/result.err"
cmp "$TMP/result.sens" "$TMP/physical/01.expected.sens"
echo 'WIDECONTEXT-ONCE-MACHINE-PASS physical=yes once=yes reentry=blocked'
