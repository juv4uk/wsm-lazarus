#!/usr/bin/env bash
# Складання й фізичні свідки; виконати ДО енергетичних вимірювань.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
OUT="$ROOT/build/energy"
mkdir -p "$OUT/bin" "$OUT/units" "$OUT/fixtures"
for item in 'scripts/energy/runtime.lpr runtime' 'src/senst5m.lpr senst5m' 'src/sensukrlisp.lpr sensukrlisp'; do
  read -r source target <<< "$item"
  fpc -B -O2 -Mobjfpc -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
    "-o$target" "$ROOT/$source"
done
python3 - "$OUT/fixtures" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
words={
 'eq': ['10','101','1','1','01'],
 'selector': ['10','100','10','111','0','1','01','01'],
 'cond32': ['10','110']+sum((['10','1' if i==31 else '0','1','01'] for i in range(32)),[])+['01'],
}
for name,w in words.items():
    (p/(name+'.words')).write_text(' '.join(w)+'\n')
    (p/(name+'.expected.words')).write_text(('0' if name=='selector' else '1')+'\n')
PY
for name in eq selector cond32; do
  "$OUT/bin/senst5m" --пакувати-слова "$OUT/fixtures/$name.words" > "$OUT/fixtures/$name.sens"
  "$OUT/bin/senst5m" --пакувати-слова "$OUT/fixtures/$name.expected.words" > "$OUT/fixtures/$name.expected.sens"
  # Проєкційний writer не перезаписує файли, тому прибираємо лише власний build output.
  rm -f "$OUT/fixtures/$name.lisp" "$OUT/fixtures/$name.roundtrip.sens"
  "$OUT/bin/sensukrlisp" --вивести-ук "$OUT/fixtures/$name.sens" "$OUT/fixtures/$name.lisp"
  "$OUT/bin/sensukrlisp" --пакувати-ук "$OUT/fixtures/$name.lisp" "$OUT/fixtures/$name.roundtrip.sens"
  cmp "$OUT/fixtures/$name.sens" "$OUT/fixtures/$name.roundtrip.sens"
  printf '2\n' | "$OUT/bin/runtime" external/sens "$OUT/fixtures/$name.sens" "$OUT/fixtures/$name.expected.sens"
done
