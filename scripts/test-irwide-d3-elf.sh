#!/usr/bin/env bash
# G6.168 — фізичні D3 через єдиний pinned WideIR→ELF, не нові закони.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout cmp readelf chmod mktemp grep cp python3; do
  command -v "$tool" >/dev/null || {
    echo "Д3-ШИРОКИЙ-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д3-ШИРОКИЙ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"

TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "Д3-ШИРОКИЙ-ПРОВАЛ код=$rc" >&2
    if [[ -s "$TMP/generator.out" ]]; then
      echo '--- Повний stdout фізичного генератора (до 100 рядків)' >&2
      tail -n 100 "$TMP/generator.out" >&2
    fi
    for log in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 14 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'echo "Д3-ШИРОКИЙ-НЕВДАЛИЙ-КРОК рядок=$LINENO" >&2' ERR
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwide-d3-elf.pas test-irwide-d3-elf' \
  'src/senswidefrontelf.lpr senswidefrontelf'; do
  read -r source exe <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build" 2>&1 || {
      cat "$TMP/$exe.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done

timeout 45s "$TMP/bin/test-irwide-d3-elf" \
  "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.168-WIDE-D3-ELF-OK positives=6 negatives=10 oracle=INTERNAL-D3 energy=NOT-MEASURED' \
  "$TMP/generator.out"
if grep -Fq 'unfreed memory blocks' "$TMP/generator.err"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/generator.err" || {
    cat "$TMP/generator.err" >&2; exit 1;
  }
fi

PASS=0
for label in \
  цитата-д7 цитата-д1 рівність-ні рівність-так \
  перше-сполучення решта-сполучення; do
  src="$TMP/physical/$label.sens"
  expected="$TMP/physical/$label.expected.sens"
  image="$TMP/physical/$label.elf"
  cli="$TMP/$label.cli.elf"
  test -s "$src" && test -s "$expected" && test -s "$image"
  timeout 25s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$src" "$cli" >"$TMP/$label.out" 2>"$TMP/$label.err"
  cmp "$cli" "$image"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.out"
  timeout 25s "$TMP/bin/senswidefrontelf" --звірити-походження \
    "$src" "$cli" >"$TMP/$label.proof" 2>"$TMP/$label.proof.err"
  # Підтвердження exact provenance — кодом завершення --звірити-походження
  # та стабільним ASCII машинним статусом (host UTF-8 не є каноном SENS).
  grep -Fq 'physical=T5M compiler=pinned-WideIR' "$TMP/$label.proof"
  readelf -h "$cli" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  chmod u+x "$cli"
  timeout 5s "$cli" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$expected" "$TMP/$label.actual.sens"
  PASS=$((PASS+1))
done
test "$PASS" -eq 6

# Фізичний ELF не можна перезаписати навіть правильним джерелом.
cp "$TMP/цитата-д7.cli.elf" "$TMP/original.elf"
if timeout 25s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
  "$TMP/physical/цитата-д7.sens" "$TMP/цитата-д7.cli.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err"; then
  echo 'Д3-ШИРОКИЙ-ПРОВАЛ: перезапис дозволено' >&2; exit 1
fi
test ! -s "$TMP/clobber.out"
cmp "$TMP/original.elf" "$TMP/цитата-д7.cli.elf"

# Той самий entry/ELF header, але підмінена одна машинна інструкція:
# походження має відхилитись, а джерело і вже зібраний ELF лишаються цілими.
python3 - "$TMP/original.elf" "$TMP/tampered.elf" <<'PY'
from pathlib import Path
import sys
raw = bytearray(Path(sys.argv[1]).read_bytes())
assert len(raw) > 121 and raw[120] != 0x90
raw[120] = 0x90
Path(sys.argv[2]).write_bytes(raw)
PY
if timeout 25s "$TMP/bin/senswidefrontelf" --звірити-походження \
  "$TMP/physical/цитата-д7.sens" "$TMP/tampered.elf" \
  >"$TMP/tamper.out" 2>"$TMP/tamper.err"; then
  echo 'Д3-ШИРОКИЙ-ПРОВАЛ: підміну ELF не виявлено' >&2; exit 1
fi
test ! -s "$TMP/tamper.out"
cmp "$TMP/original.elf" "$TMP/цитата-д7.cli.elf"

echo "Д3-ШИРОКИЙ-ELF-ГАРАЗД FPC=реальний PIE=6 виконань=6 негативів=10 походження=6 перезапис=відхилено енергія=НЕ_ВИМІРЯНО"
