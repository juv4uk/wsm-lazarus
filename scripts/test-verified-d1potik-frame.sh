#!/usr/bin/env bash
# G6.240 — справжній Linux x86-64: два окремі фізичні W1 входи
# допускаються навіть коли ядро повертає легальний short read 1+1.
# Це лише host framing для вже pinned D3:101/CMP/SETE, не SENS-закон.
# Єдиний verified-all запускає цей профіль без нового CI workflow.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д1-КАДР-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump head tail mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "Д1-КАДР-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 50s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "Д1-КАДР-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 40 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/frames" "$TMP/upstream"
for line in \
  'src/sensd1potikelf.lpr sensd1potikelf' \
  'scripts/test-elfd1potik.pas test-elfd1potik' \
  'scripts/test-sensmashyna.pas test-sensmashyna'; do
  read -r source exe <<< "$line"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.log" 2>&1 || {
    tail -n 60 "$TMP/$exe.log" >&2; exit 1;
  }
  test -x "$TMP/bin/$exe"
done
timeout 20s "$TMP/bin/test-elfd1potik" "$TMP/frames" >"$TMP/fixtures.log"
grep -Fq 'D1-POTIK-FRAMES-OK pairs=4 negatives=9' "$TMP/fixtures.log"
timeout 40s "$TMP/bin/test-sensmashyna" external/sens "$TMP/upstream" \
  >"$TMP/expected.log" 2>"$TMP/expected.err"
ELF="$TMP/d1-dynamic.elf"
timeout 15s "$TMP/bin/sensd1potikelf" --зібрати-D1-потік "$ELF" \
  >"$TMP/compiler.log" 2>"$TMP/compiler.err"
test -x "$ELF" && test ! -s "$TMP/compiler.err"
readelf -h "$ELF" >"$TMP/header.log"
grep -Eq 'Type:.*DYN' "$TMP/header.log"
tail -c +121 "$ELF" >"$TMP/machine.bin"
timeout 8s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine.bin" >"$TMP/machine.log"
grep -Eiq 'cmp[[:space:]]+r10,0x2' "$TMP/machine.log"
grep -Eiq 'lea[[:space:]]+rsi,\\[rsp\\+0x2\\]' "$TMP/machine.log"
grep -Eiq 'sete[[:space:]]+al' "$TMP/machine.log"
grep -Eiq 'cmp[[:space:]]+rax,0x1' "$TMP/machine.log"
GOOD=0
FRAGMENTED=0
RECOVERY=0
for label in тотожні-00 тотожні-01 тотожні-10 тотожні-11; do
  FRAME="$TMP/frames/$label.frame"
  EXPECT="$TMP/upstream/$label.expected.sens"
  test "$(wc -c < "$FRAME")" -eq 2
  test "$(wc -c < "$EXPECT")" -eq 1
  timeout 5s "$ELF" <"$FRAME" >"$TMP/actual.sens" 2>"$TMP/actual.err"
  test ! -s "$TMP/actual.err"
  cmp "$EXPECT" "$TMP/actual.sens"
  GOOD=$((GOOD+1))
  # Два реальні окремі write в pipe; один законний read не має
  # права вважати недоставлений другий W1 некоректною програмою.
  { head -c 1 "$FRAME"; sleep 0.06; tail -c +2 "$FRAME"; } |
    timeout 5s "$ELF" >"$TMP/fragment.sens" 2>"$TMP/fragment.err"
  test ! -s "$TMP/fragment.err"
  cmp "$EXPECT" "$TMP/fragment.sens"
  FRAGMENTED=$((FRAGMENTED+1))
  timeout 5s "$ELF" <"$FRAME" >"$TMP/again.sens" 2>"$TMP/again.err"
  test ! -s "$TMP/again.err"
  cmp "$EXPECT" "$TMP/again.sens"
  RECOVERY=$((RECOVERY+1))
done
NEG=0
for label in empty short extra bad-byte ASCII bad-first bad-second d7 extra-zero; do
  rc=0
  timeout 5s "$ELF" <"$TMP/frames/$label.frame" \
    >"$TMP/rejected.sens" 2>"$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/rejected.sens"
  grep -Fq 'Д1-ПОТІК-ВІДМОВА:' "$TMP/rejected.err"
  NEG=$((NEG+1))
done
for channel in closed full; do
  rc=0
  if [[ "$channel" == closed ]]; then
    timeout 5s "$ELF" <"$TMP/frames/тотожні-11.frame" \
      1>&- 2>"$TMP/host.err" || rc=$?
  else
    timeout 5s "$ELF" <"$TMP/frames/тотожні-11.frame" \
      >/dev/full 2>"$TMP/host.err" || rc=$?
  fi
  test "$rc" -eq 2 && test ! -s "$TMP/host.err"
  NEG=$((NEG+1))
done
test "$GOOD" -eq 4 && test "$FRAGMENTED" -eq 4 &&
  test "$RECOVERY" -eq 4 && test "$NEG" -eq 11
echo "VERIFIED-D1-FRAME-PASS fpc=checked physical=4 fragmented=1+1:4 negatives=11 recovery=4 linux=ELF64 machine=CMP-SETE EOF=checked EINTR=guarded oracle=SEPARATE energy=NOT-MEASURED"
