#!/usr/bin/env bash
# G3.36: повний позитивний ліміт D192 та пізня фізична відмова.
# Канонічні .sens байти створює чинний FPC senst5m, не Python.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
bash ./scripts/test-chyslopaket.sh
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP" <<'PY'
import pathlib
import sys

folder = pathlib.Path(sys.argv[1])
width = 192
count = 1024
words = ["0" * width if index % 2 == 0 else "1" * width
         for index in range(count)]
(folder / "правильні.txt").write_text(" ".join(words) + "\n", encoding="ascii")
wrong = list(words)
wrong[-1] = "0" * 12  # помилка ЛИШЕ у 1024-му фізичному слові
(folder / "пізня-відмова.txt").write_text(" ".join(wrong) + "\n", encoding="ascii")
with (folder / "еталон.tsv").open("w", encoding="utf-8", newline="") as output:
    output.write("слово\tдомен\tукр\tточні-біти\tтрити\tбайти\n")
    for index, bits in enumerate(words):
        first = index * (width + 1)
        last = first + width
        decimal = "0" if index % 2 == 0 else "-1"
        output.write(
            f"{index + 1}\tD192\t{decimal}\t{bits}\t"
            f"[{first},{last})\t[{first // 5},{(last + 4) // 5})\n"
        )
PY

"$BIN/senst5m" --пакувати-слова "$TMP/правильні.txt" > "$TMP/правильні.sens"
"$BIN/senschyslopaket" --перегляд-пакета D192 "$TMP/правильні.sens" > "$TMP/факт.tsv"
cmp "$TMP/еталон.tsv" "$TMP/факт.tsv"
test "$(wc -l < "$TMP/факт.tsv")" -eq 1025

"$BIN/senst5m" --пакувати-слова "$TMP/пізня-відмова.txt" > "$TMP/пізня-відмова.sens"
if "$BIN/senschyslopaket" --перегляд-пакета D192 "$TMP/пізня-відмова.sens" > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
  echo 'ПОМИЛКА: прийнято останнє фізичне слово іншої ширини' >&2
  exit 1
fi
test ! -s "$TMP/відмова.out"
test -s "$TMP/відмова.err"
grep -Fq '1024' "$TMP/відмова.err"
# Після відмови реальний той самий CLI повторно видає точний TSV.
"$BIN/senschyslopaket" --перегляд-пакета D192 "$TMP/правильні.sens" > "$TMP/повтор.tsv"
cmp "$TMP/еталон.tsv" "$TMP/повтор.tsv"
echo 'ЧИСЛОВИЙ-ПАКЕТ-МАСШТАБ-ГАРАЗД D192=1024/1024 TSV=байт-в-байт останнє-слово=відхилено stdout=атомарний'
