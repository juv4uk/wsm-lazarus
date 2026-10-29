#!/usr/bin/env bash
# G3.38 — реальне виконання фізичного T5M через UNIX stdin/stdout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'ФІЛЬТР-БЛОК: не знайдено Free Pascal' >&2
  exit 127
}
WORK="$ROOT/build/m0.2/sensfiltr-test"
BIN="$ROOT/build/m0.2/bin"
mkdir -p "$WORK/units" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$WORK/units" -FE"$BIN" -osensfiltr "$ROOT/src/sensfiltr.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$WORK/units" -FE"$BIN" -osenst5m "$ROOT/src/senst5m.lpr"

# Позитиви з чинного FPC T5M codec: D1 і D3:001 (цитата D1:1).
printf '1\n' > "$WORK/атом.words"
printf '10 001 1 01\n' > "$WORK/цитата.words"
printf '10 1\n' > "$WORK/незакрито.words"
"$BIN/senst5m" --пакувати-слова "$WORK/атом.words" > "$WORK/атом.sens"
"$BIN/senst5m" --пакувати-слова "$WORK/цитата.words" > "$WORK/цитата.sens"
"$BIN/senst5m" --пакувати-слова "$WORK/незакрито.words" > "$WORK/незакрито.sens"

"$BIN/sensfiltr" --виконати-сенс < "$WORK/атом.sens" \
  > "$WORK/атом.out" 2> "$WORK/атом.err"
test ! -s "$WORK/атом.err"
cmp "$WORK/атом.sens" "$WORK/атом.out"
"$BIN/sensfiltr" --виконати-сенс < "$WORK/цитата.sens" \
  > "$WORK/цитата.out" 2> "$WORK/цитата.err"
test ! -s "$WORK/цитата.err"
cmp "$WORK/атом.sens" "$WORK/цитата.out"

reject() {
  local name="$1" file="$2"
  if "$BIN/sensfiltr" --виконати-сенс < "$file" \
      > "$WORK/$name.out" 2> "$WORK/$name.err"; then
    echo "ФІЛЬТР-ПРОВАЛ: відхилений ввід допущено: $name" >&2
    exit 1
  fi
  test ! -s "$WORK/$name.out" || {
    echo "ФІЛЬТР-ПРОВАЛ: частковий stdout: $name" >&2
    exit 1
  }
  grep -Fq 'ФІЛЬТР-ПОМИЛКА:' "$WORK/$name.err" || {
    cat "$WORK/$name.err" >&2
    exit 1
  }
}

: > "$WORK/порожньо.sens"
printf '\363' > "$WORK/зіпсовано.sens"
cat "$WORK/атом.sens" "$WORK/зіпсовано.sens" > "$WORK/пізня-помилка.sens"
python3 - "$WORK/завеликий.sens" <<'PY'
import sys
with open(sys.argv[1], "wb") as f:
    f.write(b"\x00" * (4 * 1024 * 1024 + 1))
PY

reject порожньо "$WORK/порожньо.sens"
reject зіпсовано "$WORK/зіпсовано.sens"
reject пізня-помилка "$WORK/пізня-помилка.sens"
reject незакрито "$WORK/незакрито.sens"
reject завеликий "$WORK/завеликий.sens"
grep -Fq 'слово=' "$WORK/незакрито.err"

if "$BIN/sensfiltr" --невідомо < "$WORK/атом.sens" \
    > "$WORK/режим.out" 2> "$WORK/режим.err"; then
  echo 'ФІЛЬТР-ПРОВАЛ: невідомий режим прийнято' >&2
  exit 1
fi
test ! -s "$WORK/режим.out"
grep -Fq 'Використання:' "$WORK/режим.err"

# Після всіх відмов позитивне виконання не змінює фізичної відповіді.
"$BIN/sensfiltr" --виконати-сенс < "$WORK/атом.sens" > "$WORK/повтор.sens"
cmp "$WORK/атом.sens" "$WORK/повтор.sens"
echo 'ФІЛЬТР-ГАРАЗД: FPC=T5M/D2/binder/D3 stdin=байти stdout=канонічний T5M негативи=5 атомарність=так'
