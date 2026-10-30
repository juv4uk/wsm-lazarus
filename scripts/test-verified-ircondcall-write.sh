#!/usr/bin/env bash
# G6.235 — одна чинна FPC PR-перевірка машинного D3:110 COND/CALL ELF.
# Вхід — тільки pinned фізичний T5M. Аварія Linux stdout — host exit(2).
# Не створюємо нового SENS закону, CI workflow або Rust/Zig збірки.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export LC_ALL=C.UTF-8 LANG=C.UTF-8
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'COND-CALL-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout git cmp readelf objdump grep tail mktemp chmod; do
  command -v "$tool" >/dev/null || {
    echo "COND-CALL-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
on_exit() {
  local code=$?
  if ((code != 0)); then
    echo "COND-CALL-WRITE-ЗБІЙ code=$code" >&2
    for log in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 55 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap on_exit EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/phys"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-ircondcall "$ROOT/scripts/test-ircondcall.pas" \
  >"$TMP/build.log" 2>&1
HEAPTRC="log=$TMP/heap.log" timeout 90s \
  "$TMP/bin/test-ircondcall" "$TMP/phys" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'G6_122_OK ELF=21 NEG=17 CALL_SITES=' "$TMP/fixtures.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"

PASS=0
CLOSED=0
FULL=0
RECOVERY=0
for ELF in "$TMP"/phys/*.call.elf; do
  test -s "$ELF"
  stem="$(printf '%s' "$ELF" | sed 's/\.call\.elf$//')"
  EXPECT="$stem.expected.sens"
  test -s "$EXPECT"
  chmod 700 "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  tail -c +121 "$ELF" >"$TMP/machine.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/asm.log"
  grep -Eq 'cmp[[:space:]]+eax,edx' "$TMP/asm.log"
  grep -Eq 'jne[[:space:]]' "$TMP/asm.log"
  grep -Eq 'mov[[:space:]]+edi,0x2' "$TMP/asm.log"

  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/actual.err"
  cmp "$EXPECT" "$TMP/actual.sens"
  test ! -s "$TMP/actual.err"
  PASS=$((PASS+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.sens"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 21 && test "$CLOSED" -eq 21 && \
  test "$FULL" -eq 21 && test "$RECOVERY" -eq 21
echo 'IRCONDCALL-WRITE-PASS FPC=checked ELF=21 negative-forms=17 closed=21 full=21 recovery=21 physical=T5M independent-oracle=NOT-RUN energy=NOT-MEASURED'
