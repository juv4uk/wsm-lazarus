#!/usr/bin/env bash
# G3.36: фізичні байти числової пакетної проєкції, не SENS evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
bash ./scripts/test-numericplane.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ЧИСЛОВЕ-ПАКУВАННЯ-БЛОК: потрібен FPC' >&2; exit 127;
}
mkdir -p build/m0.2/chyslopakuvaty-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/chyslopakuvaty-units" \
  -FE"$ROOT/build/m0.2/bin" -osenschyslopakuvaty "$ROOT/src/senschyslopakuvaty.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/chyslopakuvaty-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/chyslopakuvaty-units" \
  -FE"$ROOT/build/m0.2/bin" -osenschyslopaket "$ROOT/src/senschyslopaket.lpr"
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
reject() {
  local code=0
  "$BIN/senschyslopakuvaty" "$@" >"$TMP/порожній.out" 2>"$TMP/помилка.err" || code=$?
  if [[ "$code" -ne 2 || -s "$TMP/порожній.out" || ! -s "$TMP/помилка.err" ]]; then
    echo "ПОМИЛКА: не відхилено вхід ($*) з кодом 2 та порожнім stdout (status=$code)" >&2
    exit 1
  fi
}
for width in 12 24 48 96 192; do
  python3 - "$width" "$TMP/числа.lisp" "$TMP/слова.txt" "$TMP/значення.txt" <<'PY'
from pathlib import Path
import sys
w=int(sys.argv[1])
values=[-(1 << (w-1)), -1, 0, 1, (1 << (w-1))-1]
Path(sys.argv[2]).write_text(''.join(str(v)+'\n' for v in values),encoding='ascii')
Path(sys.argv[3]).write_text(' '.join(format(v & ((1<<w)-1),f'0{w}b') for v in values)+'\n',encoding='ascii')
Path(sys.argv[4]).write_text(''.join(str(v)+'\n' for v in values),encoding='ascii')
PY
  "$BIN/senschyslopakuvaty" --пакувати-пакет "D$width" "$TMP/числа.lisp" >"$TMP/пакет.sens"
  "$BIN/senst5m" --пакувати-слова "$TMP/слова.txt" >"$TMP/еталон.sens"
  cmp "$TMP/пакет.sens" "$TMP/еталон.sens"
  "$BIN/senst5m" --перегляд "$TMP/пакет.sens" >"$TMP/назад.txt"
  cmp "$TMP/слова.txt" "$TMP/назад.txt"
  "$BIN/senschyslopaket" --перегляд-пакета "D$width" "$TMP/пакет.sens" >"$TMP/перевірка.tsv"
  python3 - "$width" "$TMP/перевірка.tsv" "$TMP/значення.txt" "$TMP/слова.txt" <<'PY'
import csv,sys
from pathlib import Path
w=int(sys.argv[1])
rows=list(csv.reader(Path(sys.argv[2]).open(encoding='utf-8'),delimiter='\t'))
values=Path(sys.argv[3]).read_text(encoding='ascii').splitlines()
bits=Path(sys.argv[4]).read_text(encoding='ascii').split()
assert len(rows)==len(values)+1, rows
for i,(row,value,word) in enumerate(zip(rows[1:],values,bits),start=1):
    assert row[:4]==[str(i),'D'+str(w),value,word],(i,row)
PY
done
# Один D12+ домен на пакет: жодного мовчазного обрізання,
# корекції проєкцій або публікації часткового T5M.
printf '%s\n' '-2048' '0' '2047' >"$TMP/добрі.lisp"
"$BIN/senschyslopakuvaty" --пакувати-пакет D12 "$TMP/добрі.lisp" >"$TMP/добрі.sens"
: > "$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n\n1\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n2048\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n-2049\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n-0\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n+1\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n 1\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '\357\273\2770\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\r1\n' >"$TMP/погані.lisp"
reject --пакувати-пакет D12 "$TMP/погані.lisp"
printf '0\n' >"$TMP/погані.txt"
reject --пакувати-пакет D12 "$TMP/погані.txt"
reject --пакувати-пакет D10 "$TMP/добрі.lisp"
reject --пакувати-пакет D12 "$TMP/відсутній.lisp"
python3 - "$TMP/погані.lisp" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('0\n'*1025,encoding='ascii')
PY
reject --пакувати-пакет D12 "$TMP/погані.lisp"
python3 - "$TMP/погані.lisp" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b'0'*131073)
PY
reject --пакувати-пакет D12 "$TMP/погані.lisp"
# CRLF є припустимим файловим роздільником, але число — незмінне.
printf -- '-1\r\n0\r\n1\r\n' >"$TMP/добрі.lisp"
"$BIN/senschyslopakuvaty" --пакувати-пакет D12 "$TMP/добрі.lisp" >"$TMP/crlf.sens"
printf '%s\n' '111111111111 000000000000 000000000001' >"$TMP/crlf.words"
"$BIN/senst5m" --пакувати-слова "$TMP/crlf.words" >"$TMP/еталон.sens"
cmp "$TMP/еталон.sens" "$TMP/crlf.sens"
# Останній LF не є обов'язковим.
printf -- '-1\n0' >"$TMP/добрі.lisp"
"$BIN/senschyslopakuvaty" --пакувати-пакет D12 "$TMP/добрі.lisp" >"$TMP/no-lf.sens"
"$BIN/senst5m" --перегляд "$TMP/no-lf.sens" >"$TMP/no-lf.words"
printf '%s\n' '111111111111 000000000000' >"$TMP/еталон.words"
cmp "$TMP/еталон.words" "$TMP/no-lf.words"
# Відновлення процесу після негативів.
printf '0\n' >"$TMP/добрі.lisp"
"$BIN/senschyslopakuvaty" --пакувати-пакет D12 "$TMP/добрі.lisp" >"$TMP/кінцевий.sens"
"$BIN/senst5m" --перегляд "$TMP/кінцевий.sens" | grep -Fxq '000000000000'
echo 'ЧИСЛОВЕ-ПАКУВАННЯ-ГАРАЗД D12-D192=5/5 фізичний=T5M байти=точні відмови=без-stdout'
