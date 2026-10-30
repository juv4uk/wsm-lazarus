#!/usr/bin/env bash
# G6.182: два реально скомпільованих D5 тіла, один двійковий T5M ABI.
# Порівнюємо FPC -O1/-O2 байт-у-байт; runtime аргументи змінюються ПІСЛЯ
# компіляції. Жодної реалізації закону ADD/SUB у хості чи SENS-проєкції.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'G6.182-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in timeout fpc git readelf cmp grep wc mktemp; do
  command -v "$cmd" >/dev/null || { echo "G6.182-БЛОК: немає $cmd" >&2; exit 127; }
done
# Тест не запускає Rust, Zig, RAPL, текстовий компілятор чи незалежний
# семантичний oracle: цей зріз перевіряє тільки native determinism.
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
[[ "$(git -C external/sens rev-parse HEAD)" == "$PIN" ]]
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "G6.182-RED rc=$rc" >&2
    for log in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 35 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/fixtures" "$TMP/fixt-units" "$TMP/fixt-bin" "$TMP/probes"
timeout 180s fpc -B -O1 -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/fixt-units" -FE"$TMP/fixt-bin" \
  -otest-bodyfile-compiler scripts/test-bodyfile-compiler.pas \
  >"$TMP/fixtures-build.log" 2>&1 || { cat "$TMP/fixtures-build.log" >&2; exit 1; }
timeout 60s "$TMP/fixt-bin/test-bodyfile-compiler" "$ROOT" "$TMP/fixtures" \
  >"$TMP/fixtures-manifest.log" 2>"$TMP/fixtures.err"
[[ "$(wc -l <"$TMP/fixtures-manifest.log")" -eq 9 ]]
grep -Fq 'BODY-FILE-FIXTURES-OK cases=9 negatives=5' "$TMP/fixtures.err"
test -s "$TMP/fixtures/add7.body.sens"
test -s "$TMP/fixtures/sub7.body.sens"

for level in 1 2; do
  mkdir -p "$TMP/opt$level-units" "$TMP/opt$level-bin"
  for row in \
    'src/sensbodyfileelf.lpr sensbodyfileelf' \
    'src/sensdvaparamstdinelf.lpr sensdvaparamstdinelf'; do
    read -r source binary <<<"$row"
    timeout 180s fpc -B "-O$level" -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/opt$level-units" -FE"$TMP/opt$level-bin" \
      "-o$binary" "$ROOT/$source" \
      >"$TMP/opt$level-$binary.log" 2>&1 || {
        cat "$TMP/opt$level-$binary.log" >&2; exit 1;
      }
    test -x "$TMP/opt$level-bin/$binary"
  done
  for op in add7 sub7; do
    base="$TMP/fixtures/$op"
    timeout 60s "$TMP/opt$level-bin/sensbodyfileelf" \
      --два-D24-stdout \
      "$base.body.sens" "$base.p1.sens" "$base.p2.sens" \
      "$base.a1.sens" "$base.a2.sens" "$TMP/opt$level-$op.static.elf" \
      >"$TMP/opt$level-$op.body.log" 2>"$TMP/opt$level-$op.body.err"
    timeout 60s "$TMP/opt$level-bin/sensdvaparamstdinelf" \
      --два-фізичні-D24-stdin \
      "$TMP/opt$level-$op.static.elf" "$TMP/opt$level-$op.dynamic.elf" \
      >"$TMP/opt$level-$op.dynamic.log" 2>"$TMP/opt$level-$op.dynamic.err"
    test ! -s "$TMP/opt$level-$op.body.err"
    test ! -s "$TMP/opt$level-$op.dynamic.err"
    grep -Fq 'args=2 exact=D24 input=10-byte-T5M' "$TMP/opt$level-$op.dynamic.log"
    readelf -h "$TMP/opt$level-$op.dynamic.elf" >"$TMP/opt$level-$op.header.log"
    grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/opt$level-$op.header.log"
    ! readelf -l "$TMP/opt$level-$op.dynamic.elf" | grep -Eq 'INTERP|DYNAMIC'
    chmod 700 "$TMP/opt$level-$op.dynamic.elf"
  done
done

# Не тільки ідентичні ELF-заголовки: порівнюємо ВЕСЬ native payload.
for op in add7 sub7; do
  cmp "$TMP/opt1-$op.static.elf" "$TMP/opt2-$op.static.elf"
  cmp "$TMP/opt1-$op.dynamic.elf" "$TMP/opt2-$op.dynamic.elf"
done
if cmp -s "$TMP/opt1-add7.dynamic.elf" "$TMP/opt1-sub7.dynamic.elf"; then
  echo 'G6.182-RED: різні D5 тіла дали однаковий машинний ELF' >&2; exit 1
fi

# Числовий test-vector — лише тестовий probe, не новий закон SENS.
# Ті самі бінарні stdin words потрібні і -O1, і -O2.
mkdir -p "$TMP/num-units" "$TMP/num-bin"
timeout 180s fpc -B -O1 -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/num-units" -FE"$TMP/num-bin" \
  -osenschyslo "$ROOT/src/senschyslo.lpr" \
  >"$TMP/numeric-build.log" 2>&1 || { cat "$TMP/numeric-build.log" >&2; exit 1; }
encode_d24() {
  local n="$1" out="$2"
  printf '%s\n' "$n" >"$TMP/probes/value.lisp"
  rm -f -- "$out"
  timeout 30s "$TMP/num-bin/senschyslo" --з-укр D24 \
    "$TMP/probes/value.lisp" "$out" >"$TMP/probes/encode.log"
  [[ "$(wc -c <"$out")" -eq 5 ]]
}
passed=0
while read -r a b sum difference; do
  encode_d24 "$a" "$TMP/probes/a.sens"
  encode_d24 "$b" "$TMP/probes/b.sens"
  cat "$TMP/probes/a.sens" "$TMP/probes/b.sens" >"$TMP/probes/input.sens"
  [[ "$(wc -c <"$TMP/probes/input.sens")" -eq 10 ]]
  for op in add7 sub7; do
    if [[ "$op" == add7 ]]; then expected="$sum"; else expected="$difference"; fi
    encode_d24 "$expected" "$TMP/probes/expected.sens"
    for level in 1 2; do
      timeout 10s "$TMP/opt$level-$op.dynamic.elf" \
        <"$TMP/probes/input.sens" >"$TMP/probes/actual.sens" \
        2>"$TMP/probes/execute.err"
      test ! -s "$TMP/probes/execute.err"
      cmp "$TMP/probes/expected.sens" "$TMP/probes/actual.sens"
      passed=$((passed+1))
    done
  done
done <<'CASES'
7 -3 4 10
-100 55 -45 -155
-2048 0 -2048 -2048
CASES
[[ "$passed" -eq 12 ]]

# Один запізнілий пошкоджений runtime кадр має давати exit=2,
# нуль фізичного stdout, однаковий за обома FPC-рівнями.
printf '\377' >"$TMP/probes/bad.sens"
rejected=0
for op in add7 sub7; do
  for level in 1 2; do
    rc=0
    timeout 10s "$TMP/opt$level-$op.dynamic.elf" \
      <"$TMP/probes/bad.sens" >"$TMP/probes/bad.out" \
      2>"$TMP/probes/bad.err" || rc=$?
    [[ "$rc" -eq 2 ]] && test ! -s "$TMP/probes/bad.out" \
      && test ! -s "$TMP/probes/bad.err"
    rejected=$((rejected+1))
  done
done
echo "G6.182-PASS optimization=O1/O2 equal-static-ELF=2 equal-runtime-ELF=2 native=12 negatives=$rejected oracle=ALREADY-VERIFIED-IN-G6.175 energy=NOT_MEASURED"
