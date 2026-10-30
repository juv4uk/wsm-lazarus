#!/usr/bin/env bash
# G6.243 — реальні D3:010 ATOM ELF64 та Linux stdout -EBADF/-ENOSPC.
# Чинний FPC gate автоматично підхоплює test-verified*.sh.
# Це перевірка host виводу 0/1 + LF, НЕ канонічна T5M проєкція
# та НЕ незалежний семантичний SENS REPL oracle.
# Вхід: 10 фізичних .sens, які створює наявний pinned FPC witness;
# вихід: 10 owned ELF64 ET_EXEC + host stdout та 14 admission негативів.
# Lifetime: build fixtures у відокремленій build/m0.2/elfatom теці,
# копії executable у приватній mktemp-директорії з очищенням через trap.
# 1) Чому два host байти не є фізичним D1 T5M?
# 2) Чому exit(0) неможливий після -EBADF/-ENOSPC?
# 3) Чому перевірка .expected.out сама по собі не SENS oracle?
# 4) Що гарантує повторне виконання того самого ELF після I/O відмови?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D3-АТОМ-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in fpc timeout git cmp mktemp grep readelf tail chmod cp; do
  command -v "$tool" >/dev/null || {
    echo "D3-АТОМ-WRITE-БЛОК: немає $tool" >&2
    exit 127
  }
done
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "D3-АТОМ-WRITE-ПРОВАЛ exit=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.log; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "build/m0.2/elfatom"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-elfatom \
  "$ROOT/scripts/test-elfatom.pas" >"$TMP/fpc.build" 2>&1 || {
    cat "$TMP/fpc.build" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 70s "$TMP/bin/test-elfatom" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2; exit 1;
  }
grep -Fq 'НАТИВНИЙ-АТОМ-ДОПУСК-ГАРАЗД D3:010=машинний позитивні=10 негативні=14' \
  "$TMP/fixtures.log"
test ! -s "$TMP/fixtures.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"

# Спільний ELF guard додає саме цей перевірений host суфікс.
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' >"$TMP/checked.bytes"
P=0; CLOSED=0; FULL=0; RECOVERY=0
for label in atom-zero atom-one atom-empty atom-d3-empty atom-cons \
  atom-cons-empty atom-cons-cons atom-atom-cons atom-atom atom-nested-cons; do
  SOURCE="build/m0.2/elfatom/$label.sens"
  EXPECT="build/m0.2/elfatom/$label.expected.out"
  IMAGE="build/m0.2/elfatom/$label.expected.elf"
  ELF="$TMP/$label.elf"
  test -s "$SOURCE" && test -s "$EXPECT" && test -s "$IMAGE"
  cp "$IMAGE" "$ELF"
  chmod 700 "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/header.log"
  grep -Eq 'Type:.*EXEC' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  tail -c 11 "$ELF" | cmp - "$TMP/checked.bytes"
  timeout 5s "$ELF" >"$TMP/normal.out" 2>"$TMP/normal.err"
  test ! -s "$TMP/normal.err"
  cmp "$EXPECT" "$TMP/normal.out"
  P=$((P+1))

  code=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  code=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovered.out" 2>"$TMP/recovered.err"
  test ! -s "$TMP/recovered.err"
  cmp "$EXPECT" "$TMP/recovered.out"
  RECOVERY=$((RECOVERY+1))
done
test "$P" -eq 10 && test "$CLOSED" -eq 10 && \
  test "$FULL" -eq 10 && test "$RECOVERY" -eq 10
echo 'D3-ATOM-ASCII-WRITE-PASS FPC=checked physical=10 ELF=10 pinned-negatives=14 closed=10 full=10 recovery=10 oracle=EXISTING-SEPARATE energy=NOT-MEASURED'
