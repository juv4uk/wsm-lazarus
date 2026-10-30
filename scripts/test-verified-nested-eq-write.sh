#!/usr/bin/env bash
# G6.238 — після трьох CALL або трьох inline EQ Linux stdout мусить
# записати повний один фізичний байт D1/T5M, інакше host exit != 0.
# Тут перевіряємо МЕХАНІЗМ; мовний оракул — окремий test-irnestedinline.sh.
# Raw машинний донор не публікуємо; фінальні ELF є checked ET_DYN.
# 1) Чому Linux syscall status не є SENS D1:0?
# 2) Чому CALL/RET та inline повинні породжувати той самий T5M?
# 3) Чому postpass застосовано після інлайн-оптимізації?
# 4) Чому успішний retry після ENOSPC необхідний у регресійному тесті?
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ВКЛАДЕНИЙ-EQ-WRITE-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc git timeout cmp mktemp grep readelf objdump tail; do
  command -v "$tool" >/dev/null || {
    echo "ВКЛАДЕНИЙ-EQ-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/phys"
FPC_BIN=$(printenv FPC || echo fpc)
if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-irnestedinline "$ROOT/scripts/test-irnestedinline.pas" \
  >"$TMP/build.log" 2>&1; then
  cat "$TMP/build.log" >&2; exit 1
fi
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-irnestedinline" \
  "$TMP/phys" >"$TMP/generator.log" 2>"$TMP/generator.err" || {
  cat "$TMP/generator.log" "$TMP/generator.err" >&2; exit 1;
}
grep -Fq 'G6_135_OK PHYSICAL=16 OPTIMIZED=16 NEGATIVE=15' "$TMP/generator.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' >"$TMP/checked-tail.bin"
PASS=0
BAD=0
RECOVERED=0
for physical in "$TMP"/phys/d3-????.sens; do
  stem="${physical%.sens}"
  [[ -s "$physical" && -s "$stem.expected.sens" ]]
  [[ $(wc -c <"$stem.expected.sens") -eq 1 ]]
  baseline="$stem.baseline.elf"
  inline="$stem.inline.elf"
  [[ -s "$baseline" && -s "$inline" ]]
  [[ $(wc -c <"$baseline") -eq $(wc -c <"$inline") ]]
  for variant in baseline inline; do
    elf="$stem.$variant.elf"
    chmod 700 "$elf"
    readelf -h "$elf" >"$TMP/header"
    grep -Eq 'Type:.*DYN' "$TMP/header"
    tail -c 11 "$elf" >"$TMP/tail"
    cmp "$TMP/checked-tail.bin" "$TMP/tail"
    tail -c +121 "$elf" >"$TMP/machine"
    objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/machine" >"$TMP/disassembly"
    if [[ "$variant" == baseline ]]; then
      [[ $(grep -Ec '[[:space:]]call[[:space:]]' "$TMP/disassembly") -eq 3 ]]
      [[ $(grep -Ec '[[:space:]]ret([[:space:]]|$)' "$TMP/disassembly") -eq 1 ]]
    else
      ! grep -Eq '[[:space:]](call|ret)([[:space:]]|$)' "$TMP/disassembly"
      [[ $(grep -Ec '[[:space:]]sete[[:space:]]' "$TMP/disassembly") -eq 3 ]]
    fi
    timeout 5s "$elf" >"$TMP/answer.sens" 2>"$TMP/stderr"
    test ! -s "$TMP/stderr"
    cmp "$TMP/answer.sens" "$stem.expected.sens"
    PASS=$((PASS+1))
    for destination in closed full; do
      rc=0
      if [[ "$destination" == closed ]]; then
        timeout 5s "$elf" 1>&- 2>"$TMP/stderr" || rc=$?
      else
        timeout 5s "$elf" > /dev/full 2>"$TMP/stderr" || rc=$?
      fi
      [[ "$rc" -eq 1 ]]
      test ! -s "$TMP/stderr"
      BAD=$((BAD+1))
    done
    timeout 5s "$elf" >"$TMP/recovered.sens" 2>"$TMP/stderr"
    test ! -s "$TMP/stderr"
    cmp "$TMP/recovered.sens" "$stem.expected.sens"
    RECOVERED=$((RECOVERED+1))
  done
done
[[ "$PASS" -eq 32 && "$BAD" -eq 64 && "$RECOVERED" -eq 32 ]]
echo "VERIFIED-NESTED-EQ-WRITE-PASS fpc=checked native=$PASS closed-and-full=$BAD recovery=$RECOVERED admission-negative=15 pinned-oracle=EXISTING-SEPARATE energy=NOT-MEASURED"
