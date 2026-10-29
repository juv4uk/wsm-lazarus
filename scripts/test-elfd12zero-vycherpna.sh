#!/usr/bin/env bash
# G6.101: 4096 окремих канонічних W12 -> один незмінний машинний ELF.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-ВИЧЕРПНО-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN="${FPC:-fpc}"
for tool in "$FPC_BIN" timeout python3 mktemp cmp readelf; do
  command -v "$tool" >/dev/null || {
    echo "Д12-ВИЧЕРПНО-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP="$(mktemp -d)"
trap 'status=$?; if (( status != 0 )); then
  echo "Д12-ВИЧЕРПНО-ВІДМОВА: код=$status" >&2;
  for f in "$TMP"/*.log; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
  done;
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/data"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd12zero-vycherpna \
  "$ROOT/scripts/test-elfd12zero-vycherpna.pas" >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-elfd12zero-vycherpna" "$TMP/data" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fxq 'D12-EXHAUSTIVE-OK cases=4096 elf=1' "$TMP/generator.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
cmp "$TMP/data/stream.elf" "$TMP/data/stream-repeated.elf"
chmod 700 "$TMP/data/stream.elf"
readelf -h "$TMP/data/stream.elf" >"$TMP/header.log"
grep -Eq 'Type:.*DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
timeout 900s python3 - "$TMP/data" <<'PY'
import hashlib
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
elf = root / "stream.elf"
atoms = (root / "atoms.bin").read_bytes()
answers = (root / "answers.bin").read_bytes()
assert len(atoms) == 4096 * 3 and len(answers) == 4096
before = hashlib.sha256(elf.read_bytes()).digest()
all_words = [atoms[i * 3:(i + 1) * 3] for i in range(4096)]
assert len(set(all_words)) == 4096, "колізія двійкових D12 слів"
assert len(set(answers)) == 2, "D1 має містити 0 та 1"

def run(data):
    return subprocess.run([str(elf)], input=data, capture_output=True,
                          check=False, timeout=4)

for i, word in enumerate(all_words):
    proc = run(word)
    if proc.returncode != 0 or proc.stdout != answers[i:i + 1] or proc.stderr:
        raise RuntimeError(
            f"порушення D12→D1 на індексі {i}, D12={i - 2048}: "
            f"rc={proc.returncode} stdout={proc.stdout.hex()} "
            f"expected={answers[i:i + 1].hex()} stderr={proc.stderr!r}"
        )

zero = all_words[2048]
assert answers.count(answers[2048:2049]) == 1, "єдиний нуль D12"
negative = [b"", zero[:1], zero[:2], zero + b"\x00",
            zero + b"\n", zero + zero]
# Для кожного W5/W5/W2 байта навмисно обираємо фізично
# неканонічні значення. Валідні байти визначає тільки
# вже створений T5M корпус, а не текстовий / ASCII dispatch.
for offset in range(3):
    admitted = {word[offset] for word in all_words}
    invalid = [x for x in range(256) if x not in admitted]
    assert len(invalid) >= 20
    for bad in invalid[:20]:
        damaged = bytearray(zero)
        damaged[offset] = bad
        negative.append(bytes(damaged))
for i, word in enumerate(negative):
    proc = run(word)
    if proc.returncode != 2 or proc.stdout or (
        not proc.stderr.startswith("Д12-ПОТІК-ВІДМОВА".encode("utf-8"))
    ):
        raise RuntimeError(
            f"хибне прийняття пошкодженого T5M #{i}: "
            f"rc={proc.returncode} stdout={proc.stdout.hex()} "
            f"stderr={proc.stderr!r}"
        )
# Після 66 відмов той самий код знову виконує обидва результати.
for at in (2048, 0, 4095):
    proc = run(all_words[at])
    assert proc.returncode == 0 and proc.stderr == b""
    assert proc.stdout == answers[at:at + 1], "невдале відновлення"
after = hashlib.sha256(elf.read_bytes()).digest()
assert before == after, "ELF мутував під час виконання"
print(f"Д12-ВИЧЕРПНО-ГАРАЗД фізичних=4096 негативів={len(negative)} "
      "відновлення=3 ELF=незмінний T5M=точно енергія=НЕ-ВИМІРЯНО")
PY
