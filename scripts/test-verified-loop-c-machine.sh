#!/usr/bin/env bash
# G6.241 — guard проти недійсного енергобенчмарка: GCC -O2 не вправі
# перетворити N реальних C додавань в mov/ret після constant-fold.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'LOOP-C-МАШИНА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in gcc objdump python3 mktemp timeout; do
  command -v "$tool" >/dev/null || {
    echo "LOOP-C-МАШИНА-БЛОК: немає $tool" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Дизасемблювати тільки main, не startup/glibc: backward branch
# і арифметика в її тілі потрібні для вимірюваного циклу.
check_machine() {
  local image="$1" want_loop="$2" dis="$3"
  objdump -d -M intel --disassemble=main "$image" >"$dis"
  python3 - "$dis" "$want_loop" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
wanted = sys.argv[2] == 'yes'
rows = []
for line in text.splitlines():
    m = re.match(r'^\s*([0-9a-f]+):\s+(?:[0-9a-f]{2}\s+)+([a-z][a-z0-9]*)\s*(.*)$', line)
    if m:
        rows.append((int(m[1], 16), m[2], m[3]))
assert rows, 'відсутні машинні інструкції main'
loops = []
for at, op, arg in rows:
    if not op.startswith('j') or op in ('jmp', 'jmpq'):
        continue
    target = re.match(r'^(?:0x)?([0-9a-f]+)(?:\s|$)', arg)
    if target and int(target[1], 16) < at:
        start = int(target[1], 16)
        body = [name for address, name, _ in rows if start <= address < at]
        if any(name in ('add', 'sub', 'imul') for name in body):
            loops.append((start, at))
if wanted:
    assert loops, f'GCC оптимізував C цикл або він не містить ALU: {rows!r}'
else:
    assert not loops, 'контрольний згортаний цикл несподівано лишився'
print('LOOP-C-MACHINE-OK' if wanted else 'LOOP-C-CONTROL-FOLDED',
      'machine-loops=', len(loops), 'instructions=', len(rows))
PY
}
for row in '1000000 1' '1000001 -7'; do
  read -r count increment <<< "$row"
  exe="$TMP/c-$count"
  timeout 30s gcc -O2 "-DLOOP_N=$count" "-DLOOP_K=$increment" \
    -o "$exe" "$ROOT/benchmarks/cross-language/loop/loop.c"
  check_machine "$exe" yes "$TMP/c-$count.dis"
  want=$(( ((count % 256)*(increment % 256)+256*256) % 256 ))
  rc=0
  timeout 6s "$exe" || rc=$?
  [[ "$rc" -eq "$want" ]] || {
    echo "LOOP-C-ОРАКУЛ-ЗБІЙ: N=$count K=$increment exit=$rc очікувано=$want" >&2
    exit 1
  }
done

# Свідок попереднього дефекту: той самий оптимізаційний профіль
# із C циклом БЕЗ register barrier має зникнути в mov/ret.
cat > "$TMP/old.c" <<'C'
int main(void) {
  unsigned long long acc=0;
  for (unsigned long long i=0;i<1000000ULL;++i) acc+=1ULL;
  return (int)(acc&255ULL);
}
C
timeout 30s gcc -O2 -o "$TMP/folded" "$TMP/old.c"
check_machine "$TMP/folded" no "$TMP/folded.dis"
echo 'VERIFIED-LOOP-C-MACHINE-PASS gcc-O2=2 native-loops=2 folded-control=1 oracle=2 measured-joules=NO rust-fpc-parity=NOT-CHECKED'
