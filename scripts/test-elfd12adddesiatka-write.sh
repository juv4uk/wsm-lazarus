#!/usr/bin/env bash
# G6.223: реальний x86-64 D12 ADD -> десяткова host-проєкція (не .sens).
# Linux sys_write повинен записати ВСІ обчислені машинним кодом байти.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-ДЕСЯТКОВИЙ-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for cmd in fpc timeout readelf objdump cmp od mktemp git grep; do
  command -v "$cmd" >/dev/null || {
    echo "Д12-ДЕСЯТКОВИЙ-WRITE-БЛОК: відсутній $cmd" >&2; exit 127
  }
done
test -c /dev/full
timeout 90s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc != 0)); then
    echo "Д12-ДЕСЯТКОВИЙ-WRITE-ПРОВАЛ code=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/u-cli" "$TMP/u-fixture" "$TMP/свідки"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/u-cli" -FE"$TMP/bin" \
  -osensd12adddesiatka "$ROOT/src/sensd12adddesiatka.lpr" \
  >"$TMP/cli.log" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/u-fixture" -FE"$TMP/bin" \
  -otest-elfd12adddesiatka "$ROOT/scripts/test-elfd12adddesiatka.pas" \
  >"$TMP/fixture.log" 2>&1
timeout 30s "$TMP/bin/test-elfd12adddesiatka" "$TMP/свідки" \
  >"$TMP/fixture.out" 2>"$TMP/fixture.err"
grep -Fq 'позитивних=6' "$TMP/fixture.out"
GOOD=0
BAD=0
RECOVERY=0
# Фактично чотири довжини: "5\\n" 2; "-5\\n" 3;
# "2047\\n" 5; "-2048\\n" 6 байтів.
for row in '01 2' '03 3' '04 5' '05 6'; do
  read -r label count <<<"$row"
  ELF="$TMP/$label.elf"
  program_text="$(cat "$TMP/свідки/$label.prohrama")"
  timeout 20s "$TMP/bin/sensd12adddesiatka" --додати-десятково \
    "$program_text" "$ELF" >"$TMP/$label.build.out" \
    2>"$TMP/$label.build.err"
  test -x "$ELF" && test ! -s "$TMP/$label.build.err"
  grep -Fq 'опкод-add=01d8' "$TMP/$label.build.out"
  timeout 5s readelf -h "$ELF" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$ELF" of="$TMP/$label.code" bs=1 skip=120 status=none
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+eax,ebx' "$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+rax,rdx' "$TMP/$label.dis"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/$label.dis"
  timeout 5s "$ELF" >"$TMP/$label.actual" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  cmp "$TMP/свідки/$label.stdout" "$TMP/$label.actual"
  test "$(wc -c <"$TMP/$label.actual")" -eq "$count"
  GOOD=$((GOOD+1))

  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/$label.exec.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.exec.err"
  BAD=$((BAD+1))
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/$label.exec.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.exec.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" >"$TMP/$label.recovered" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  cmp "$TMP/$label.actual" "$TMP/$label.recovered"
  cmp "$TMP/свідки/$label.stdout" "$TMP/$label.recovered"
  RECOVERY=$((RECOVERY+1))
done
test "$GOOD" -eq 4 && test "$BAD" -eq 8 && test "$RECOVERY" -eq 4
echo "Д12-ДЕСЯТКОВИЙ-WRITE-ГАРАЗД positives=$GOOD negatives=$BAD recovery=$RECOVERY lengths=2,3,5,6 machine=ADD/CMP/JNE host-projection=decimal pinned-SENS=checked oracle=NOT-RUN energy=NOT-MEASURED"
