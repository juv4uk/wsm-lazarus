#!/usr/bin/env bash
# G5.67 — пакет через pinned D7-маршрутизатор, без нового evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
for cmd in fpc timeout cmp python3 grep mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "CORE1-ПАКЕТ-БЛОК: немає $cmd" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then echo "CORE1-ПАКЕТ-ПРОВАЛ rc=$rc" >&2; for log in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 24 "$log" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
no_leak() {
  local f="$1"
  if grep -Fq 'unfreed memory blocks' "$f" &&
     ! grep -Eq '(^| )0 unfreed memory blocks' "$f"; then
    echo "CORE1-ПАКЕТ-ПРОВАЛ: heaptrc витік у $f" >&2
    cat "$f" >&2; exit 1
  fi
}
mkdir -p "$TMP/bin" "$TMP/units"
for entry in "src/senscore1paket.lpr:senscore1paket" "scripts/test-core1-paket.pas:test-core1-paket"; do
  IFS=: read -r source name <<< "$entry"
  fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" -o"$name" "$ROOT/$source" \
    >"$TMP/build-$name.log" 2>&1 || {
      cat "$TMP/build-$name.log" >&2; exit 1;
    }
done
timeout 60s "$TMP/bin/test-core1-paket" "$ROOT/external/sens" "$ROOT" "$TMP" \
  >"$TMP/fixture.out" 2>"$TMP/fixture.err"
grep -Fq 'CORE1-PAKET-FIXTURES-OK' "$TMP/fixture.out"
no_leak "$TMP/fixture.err"
good=0
for case_name in one three sixtyfour; do
  timeout 60s "$TMP/bin/senscore1paket" --виконати-пакет "$ROOT" \
    <"$TMP/$case_name.sens" >"$TMP/$case_name.result.sens" \
    2>"$TMP/$case_name.err"
  cmp "$TMP/$case_name.expected.sens" "$TMP/$case_name.result.sens"
  test -s "$TMP/$case_name.result.sens"
  no_leak "$TMP/$case_name.err"
  good=$((good+1))
done
: > "$TMP/empty.sens"
python3 - "$TMP" "$ROOT" <<'PY'
from pathlib import Path
import sys
t = Path(sys.argv[1])
root = Path(sys.argv[2])
(t / 'damaged.sens').write_bytes((t/'three.sens').read_bytes()+bytes([243]))
(t / 'overlimit.sens').write_bytes(bytes([255]) * (4 * 1024 * 1024 + 1))
(t / 'text-lisp.sens').write_bytes((root/'external/sens/lib/core1.lisp').read_bytes())
PY
bad=0
reject() {
  local which="$1" needle="$2" rc=0
  timeout 45s "$TMP/bin/senscore1paket" --виконати-пакет "$ROOT" \
    <"$TMP/$which.sens" >"$TMP/failed.out" 2>"$TMP/failed.err" || rc=$?
  if [[ "$rc" != 2 ]] || [[ -s "$TMP/failed.out" ]] || \
     ! grep -Fq 'CORE1-ПАКЕТ-ПОМИЛКА:' "$TMP/failed.err"; then
    echo "CORE1-ПАКЕТ-ПРОВАЛ: $which rc=$rc має бути 2 та порожній stdout" >&2
    cat "$TMP/failed.err" >&2; exit 1
  fi
  if [[ -n "$needle" ]]; then
    grep -Fq "$needle" "$TMP/failed.err" || {
      echo "CORE1-ПАКЕТ-ПРОВАЛ: $which без діагностики $needle" >&2
      cat "$TMP/failed.err" >&2; exit 1
    }
  fi
  no_leak "$TMP/failed.err"
  bad=$((bad+1))
}
reject empty 'порожній'
reject damaged ''
reject overlimit 'межу'
reject broken-d2 ''
reject sixtyfive '1..64'
reject late-bad 'форма=64'
reject known-blocked 'форма=1 відоме визначення Core1 поки не підтримано виконавцем'
reject text-lisp ''
rc=0
"$TMP/bin/senscore1paket" --невідомий-режим "$ROOT" \
  <"$TMP/one.sens" >"$TMP/bad-mode.out" 2>"$TMP/bad-mode.err" || rc=$?
test "$rc" -eq 64 && test ! -s "$TMP/bad-mode.out"
grep -Fq 'Використання:' "$TMP/bad-mode.err"
bad=$((bad+1))
echo "CORE1-ПАКЕТ-ГАРАЗД реальний-FPC=так позитиви=$good негативи=$bad корені=1/3/64 один-маршрутизатор=так D7-перевірено=96 D1/W24=так stdout=T5M-побайтово пізня-відмова=без-байтів"
