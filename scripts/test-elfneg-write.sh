#!/usr/bin/env bash
# G6.213 — fail-closed машинного stdout для фізичних D12/D24 NEG.
# Нові моделі законів/проєкцій відсутні: fixtures — чинний numericplane.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-NEG-ЗАПИС-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp grep mktemp wc tail chmod; do
  command -v "$tool" >/dev/null || {
    echo "Д12-NEG-ЗАПИС-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc)); then
    for file in "$TMP"/*.build.log "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 20 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/witness"
for row in 'src/sensd12negelf.lpr:sensd12negelf' \
           'scripts/test-elfd12neg.pas:test-elfd12neg'; do
  IFS=: read -r src name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 20s "$TMP/bin/test-elfd12neg" "$TMP/witness" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
# Наявність десяти справжніх фізичних пар перевіряємо файлами,
# а не локалізованим WriteLn із залежним від locale кодуванням FPC.
# Це не відмова від позитивних/негативних машинних перевірок.
test "$(find "$TMP/witness" -maxdepth 1 -type f -name '*-in.sens' | wc -l)" -eq 10
test "$(find "$TMP/witness" -maxdepth 1 -type f -name '*-expected.sens' | wc -l)" -eq 10
test ! -s "$TMP/fixtures.err" || grep -Fq '0 unfreed memory blocks' "$TMP/fixtures.err"
pass=0
closed=0
recovered=0
wide=0
for label in 01 02 03 04 05 06 07 08 09 10; do
  elf="$TMP/$label.elf"
  timeout 20s "$TMP/bin/sensd12negelf" --змінити-знак-D12 \
    "$TMP/witness/$label-in.sens" "$elf" \
    >"$TMP/$label.status" 2>"$TMP/$label.build.err"
  test ! -s "$TMP/$label.build.err" || grep -Fq '0 unfreed memory blocks' "$TMP/$label.build.err"
  grep -Fq 'machine-neg=1 stdout=T5M' "$TMP/$label.status"
  test -s "$elf"
  chmod 700 "$elf"
  readelf -h "$elf" >"$TMP/$label.elfheader"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.elfheader"
  expected="$TMP/witness/$label-expected.sens"
  outbytes="$(wc -c <"$expected")"
  [[ "$outbytes" == 3 || "$outbytes" == 5 ]] || exit 2
  if [[ "$outbytes" == 5 ]]; then wide=$((wide+1)); fi
  tail -c +121 "$elf" >"$TMP/$label.code"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.code" >"$TMP/$label.asm"
  grep -Eiq 'neg[[:space:]]+eax' "$TMP/$label.asm"
  grep -Eiq "cmp[[:space:]]+rax,0x$outbytes" "$TMP/$label.asm"
  grep -Eiq '(^|[[:space:]])jne[[:space:]]' "$TMP/$label.asm"
  timeout 5s "$elf" >"$TMP/$label.output.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$expected" "$TMP/$label.output.sens"
  pass=$((pass+1))
  # Негативний справжній syscall: закритий fd 1 -> Linux -EBADF.
  code=0
  timeout 5s "$elf" 1>&- 2>"$TMP/$label.closed.err" || code=$?
  [[ "$code" == 2 ]] || {
    echo "Д12-NEG-ЗАПИС-ПРОВАЛ: $label повернув $code замість 2" >&2
    exit 1
  }
  test ! -s "$TMP/$label.closed.err"
  closed=$((closed+1))
  # Новий процес повинен відтворити незмінний T5M після відмови.
  timeout 5s "$elf" >"$TMP/$label.recovered.sens" 2>"$TMP/$label.recovered.err"
  test ! -s "$TMP/$label.recovered.err"
  cmp "$expected" "$TMP/$label.recovered.sens"
  recovered=$((recovered+1))
done
[[ "$pass" == 10 && "$closed" == 10 && "$recovered" == 10 && "$wide" == 1 ]]
echo "Д12-NEG-ЗАПИС-ГАРАЗД machine=$pass closed=$closed recovery=$recovered D24=$wide energy=NOT-MEASURED oracle=NOT-RUN"
