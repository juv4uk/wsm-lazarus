#!/usr/bin/env bash
# G3.19 — реальний binary pipe до вже злитого native D3 пакетного виконавця.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ПОТІК-D3-БЛОК: FPC відсутній' >&2; exit 127; }
# Стабільні фізичні oracle-fixtures — з уже злитого G3.17.
bash scripts/test-paketd3-cli.sh
DIR="$ROOT/build/potikd3"
FIX="$ROOT/build/paketd3-cli/fixtures"
FILE_RESULT="$ROOT/build/paketd3-cli/result"
mkdir -p "$DIR/units" "$DIR/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# -gh НЕ МОЖНА до бінарного stdout: heaptrc друкує діагностичний текст.
# Окремий чинний G3.16/G3.17 тест вище збирається з -gh і перевіряє 0 leaks.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$DIR/units" -FE"$DIR/bin" -osenspotikd3 "$ROOT/src/senspotikd3.lpr"
BIN="$DIR/bin/senspotikd3"
ok() {
  local label="$1"
  "$BIN" --потік external/sens < "$FIX/$label.sens" \
    > "$TMP/$label.out" 2> "$TMP/$label.err"
  [[ ! -s "$TMP/$label.err" ]] || {
    cat "$TMP/$label.err" >&2; echo "ПОТІК-D3-БЛОК: stderr при $label" >&2; exit 1;
  }
  cmp "$FIX/$label-answer.sens" "$TMP/$label.out"
  cmp "$FILE_RESULT/$label.sens" "$TMP/$label.out"
}
bad() {
  local label="$1" input="$2"; shift 2
  if "$BIN" "$@" < "$input" > "$TMP/bad.out" 2> "$TMP/bad.err"; then
    echo "ПОТІК-D3-БЛОК: помилково прийнято $label" >&2; exit 1
  fi
  [[ ! -s "$TMP/bad.out" ]] || {
    echo "ПОТІК-D3-БЛОК: частковий stdout ($label)" >&2; exit 1;
  }
  grep -Fq 'ПОМИЛКА-ПОТІК-D3' "$TMP/bad.err" || {
    echo "ПОТІК-D3-БЛОК: відсутня діагностика ($label)" >&2;
    cat "$TMP/bad.err" >&2; exit 1;
  }
}
ok one
ok four
ok 64
: > "$TMP/empty.sens"
bad 'EOF' "$TMP/empty.sens" --потік external/sens
bad 'неканонічний T5M' "$FIX/bad-t5m.sens" --потік external/sens
bad '65 коренів' "$FIX/65.sens" --потік external/sens
bad 'пізня D3 відмова' "$FIX/late-bad.sens" --потік external/sens
grep -Fq 'форма=2 слово=2' "$TMP/bad.err"
bad 'D12+ не підтримано' "$FIX/d12.sens" --потік external/sens
printf '(як-є ())\n' > "$TMP/source.lisp"
bad 'українська проєкція .lisp не машинний потік' "$TMP/source.lisp" --потік external/sens
# Обірваний кадр: останній байт валідного чотириформового пакета відсутній.
size=$(wc -c < "$FIX/four.sens")
head -c "$((size-1))" "$FIX/four.sens" > "$TMP/truncated.sens"
bad 'обрізаний T5M' "$TMP/truncated.sens" --потік external/sens
head -c 70000 /dev/zero > "$TMP/too-large.sens"
bad 'перевищено 64 KiB' "$TMP/too-large.sens" --потік external/sens
bad 'невідомий корінь pinned' "$FIX/one.sens" --потік "$TMP/nonexistent-authority"
bad 'невідомий режим' "$FIX/one.sens" --невідомий external/sens
bad 'відсутні аргументи' "$FIX/one.sens"
echo 'ПОТІК-D3-ГАРАЗД: FPC=справжній stdin=фізичний-T5M stdout=побайтовий 1/4/64 негативних=11 без-передчасного-stdout=так Core4/REPL/D12+=НЕ-ДОВЕДЕНО'
