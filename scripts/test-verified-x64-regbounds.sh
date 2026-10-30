#!/usr/bin/env bash
# G6.261 — один легкий FPC регресійний тест чотирьох наявних кодерів.
# Замість дублювання GNU as/ELF користуємось чинними повними перевірками
# ALU, CMOV, BSF/BSR і SHIFT у scripts/test-verified-all.sh.
# Тут перевіряємо лише fail-closed host enum та збереження буферів.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export LC_ALL=C.UTF-8 LANG=C.UTF-8
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'G6.261-РЕГІСТРИ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout mktemp grep tail; do
  command -v "$tool" >/dev/null || {
    echo "G6.261-РЕГІСТРИ-БЛОК: немає $tool" >&2; exit 127;
  }
done
TMP="$(mktemp -d)"
clean() {
  local status=$?
  if ((status)); then
    echo "G6.261-РЕГІСТРИ-ЗБІЙ code=$status" >&2
    for log in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$log" ]] || tail -n 60 "$log" >&2
    done
  fi
  rm -rf "$TMP"
}
trap clean EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 150s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-verified-x64-regbounds \
  "$ROOT/scripts/test-verified-x64-regbounds.pas" \
  >"$TMP/build.log" 2>&1
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-verified-x64-regbounds" \
  >"$TMP/test.log" 2>"$TMP/test.err"
grep -Fxq 'G6.261-X64-REGBOUNDS-PASS negatives=38 recovery=5 coders=4' "$TMP/test.log"
test ! -s "$TMP/test.err"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
echo 'G6.261-VERIFIED-X64-REGBOUNDS-PASS checked-FPC=YES negatives=38 recovery=5 coders=4 oracle=NOT-RUN energy=NOT-MEASURED'
