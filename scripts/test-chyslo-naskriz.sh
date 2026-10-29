#!/usr/bin/env bash
# G3.38: наскрізна механічна перевірка числових проєкцій D12–D192.
# Семантичний закон бере лише pinned SENS; тест НЕ доводить виконання арифметики.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

./scripts/check-pin.sh
# Збираємо справжні FPC CLI з увімкненими -Cr -Co -Ci; не послаблюємо попередні gate.
bash ./scripts/test-chyslopakuvaty.sh
bash ./scripts/test-chyslopaket.sh
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

reject_late() {
  local exit_code=0
  "$BIN/senschyslopakuvaty" --пакувати-пакет "$1" "$2" > "$TMP/відхилено.out" 2> "$TMP/відхилено.err" || exit_code=$?
  if [[ "$exit_code" -ne 2 || -s "$TMP/відхилено.out" || ! -s "$TMP/відхилено.err" ]]; then
    printf 'ПОМИЛКА: неатомарна числова відмова D%s (код %s)\n' "$1" "$exit_code" >&2
    exit 1
  fi
}

for width in 12 24 48 96 192; do
  # Незалежний від Pascal розрахунок exact двійкових слів, фізичних адрес
  # і двійкового доповняльного коду; Python тут створює лише еталонні дані.
  python3 - "$TMP" "$width" <<'PY'
from pathlib import Path
import random
import sys

folder = Path(sys.argv[1])
w = int(sys.argv[2])
low, high = -(1 << (w - 1)), (1 << (w - 1)) - 1
rng = random.Random(20261029 + w)
values = [low, low + 1, -100, -2, -1, 0, 1, 2, 100, high - 1, high]
values += [rng.randint(low, high) for _ in range(257 - len(values))]
assert len(values) == 257
bits = [format(v & ((1 << w) - 1), f"0{w}b") for v in values]
assert all(len(word) == w for word in bits)
(folder / "числа.lisp").write_text("\n".join(map(str, values)) + "\n", encoding="ascii")
(folder / "біти.txt").write_text(" ".join(bits) + "\n", encoding="ascii")
with (folder / "еталон.tsv").open("w", encoding="utf-8", newline="") as out:
    out.write("слово\tдомен\tукр\tточні-біти\tтрити\tбайти\n")
    for index, (value, word) in enumerate(zip(values, bits)):
        first = index * (w + 1)
        last = first + w
        out.write(
            f"{index + 1}\tD{w}\t{value}\t{word}\t"
            f"[{first},{last})\t[{first // 5},{(last + 4) // 5})\n"
        )
# Допущений префікс; пошкодження тільки останнього десяткового атома.
(folder / "пізня-помилка.lisp").write_text(
    "\n".join(map(str, values)) + "\n00\n", encoding="ascii"
)
# Відмова на переповненні після всіх правильних атомів.
(folder / "переповнення.lisp").write_text(
    "\n".join(map(str, values)) + f"\n{high + 1}\n", encoding="ascii"
)
PY
  "$BIN/senschyslopakuvaty" --пакувати-пакет "D$width" "$TMP/числа.lisp" > "$TMP/дійсний.sens"
  "$BIN/senst5m" --пакувати-слова "$TMP/біти.txt" > "$TMP/еталон.sens"
  cmp "$TMP/еталон.sens" "$TMP/дійсний.sens"
  "$BIN/senschyslopaket" --перегляд-пакета "D$width" "$TMP/дійсний.sens" > "$TMP/дійсний.tsv"
  cmp "$TMP/еталон.tsv" "$TMP/дійсний.tsv"
  # Перетворюємо тільки людський стовпець «укр» назад на проєкцію.
  python3 - "$TMP/дійсний.tsv" "$TMP/відновлені.lisp" "$width" <<'PY'
import csv
from pathlib import Path
import sys
with open(sys.argv[1], encoding="utf-8", newline="") as source:
    rows = list(csv.reader(source, delimiter="\t"))
assert rows[0] == ["слово", "домен", "укр", "точні-біти", "трити", "байти"]
assert len(rows) == 258
assert all(row[1] == "D" + sys.argv[3] for row in rows[1:])
Path(sys.argv[2]).write_text("\n".join(row[2] for row in rows[1:]) + "\n", encoding="ascii")
PY
  "$BIN/senschyslopakuvaty" --пакувати-пакет "D$width" "$TMP/відновлені.lisp" > "$TMP/повтор.sens"
  cmp "$TMP/еталон.sens" "$TMP/повтор.sens"
  reject_late "D$width" "$TMP/пізня-помилка.lisp"
  reject_late "D$width" "$TMP/переповнення.lisp"
  # Після негативів жодне старе значення або фізичний буфер не впливає на результат.
  "$BIN/senschyslopakuvaty" --пакувати-пакет "D$width" "$TMP/числа.lisp" > "$TMP/відновлення.sens"
  cmp "$TMP/еталон.sens" "$TMP/відновлення.sens"
  printf 'ЧИСЛОВИЙ-НАСКРІЗНИЙ D%s: 257 точних слів, T5M/TSV/відновлення байт-в-байт; 2 пізні відмови\n' "$width"
done

echo 'ЧИСЛОВИЙ-НАСКРІЗНИЙ-ГАРАЗД 5 доменів 1285 слів; канонічний .sens / українська .lisp проєкція'
