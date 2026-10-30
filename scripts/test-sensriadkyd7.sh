#!/usr/bin/env bash
# G1.46 — фізичний D7, pinned шість поверхонь, без семантичного dispatch.
set -euo pipefail
export LANG=C.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
for command_name in "$FPC_BIN" timeout cmp python3 git; do
  command -v "$command_name" >/dev/null || {
    echo "РЯДКИ-Д7-БЛОК: немає $command_name" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Для будь-якої відмови покажи точне місце й stderr тестового CLI.
trap 'code=$?; echo "РЯДКИ-Д7-ЗБІЙ line=$LINENO exit=$code" >&2; for log in "$TMP"/*.err; do if [[ -s "$log" ]]; then echo "--- $log ---" >&2; tail -20 "$log" >&2; fi; done' ERR
mkdir -p "$TMP/units" "$TMP/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$TMP/units" -FE"$TMP/bin" -osensriadkyd7 \
  "$ROOT/src/sensriadkyd7.lpr" >"$TMP/build.log" 2>&1 || {
  cat "$TMP/build.log" >&2; exit 1;
}
test -x "$TMP/bin/sensriadkyd7"
# Не дозволяти іншому codec підмінити незалежного upstream свідка.
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show "$PIN:scripts/sens_t5_t5m_codec.py" >"$TMP/pinned-codec.py"
test "$(git hash-object "$TMP/pinned-codec.py")" = \
  e8b92ced6fb1b8d7c18ab397ed2a1a00432e923e
CLI="$TMP/bin/sensriadkyd7"
P="external/sens"
printf '0101100 1110111\n' >"$TMP/expected.words"
python3 - "$TMP/expected.sens" "$TMP/pinned-codec.py" <<'PY'
import importlib.util, pathlib, sys
source = pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("pinned_t5m", source)
assert spec and spec.loader
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)
physical = codec.encode_t5m_projection("0101100 1110111")
assert codec.decode_t5m_bytes(physical) == ["0101100", "1110111"]
pathlib.Path(sys.argv[1]).write_bytes(physical)
PY
# Вхідна одиниця — один pinned surface-токен на рядок, не програма .lisp.
printf 'б\nц\n' >"$TMP/uk.txt"
cp "$TMP/uk.txt" "$TMP/ukr.txt"
cp "$TMP/uk.txt" "$TMP/sym.txt"
printf '","\n"◌ai"\n' >"$TMP/san.txt"
printf '","\nw\n' >"$TMP/en.txt"
OK=0
for projection in ук укр san en sym; do
  case "$projection" in
    ук) input="$TMP/uk.txt" ;;
    укр) input="$TMP/ukr.txt" ;;
    san) input="$TMP/san.txt" ;;
    en) input="$TMP/en.txt" ;;
    sym) input="$TMP/sym.txt" ;;
  esac
  timeout 15s "$CLI" "$P" --пакувати "$projection" "$input" \
    >"$TMP/$projection.sens" 2>"$TMP/$projection.err"
  test ! -s "$TMP/$projection.err"
  cmp "$TMP/expected.sens" "$TMP/$projection.sens"
  timeout 15s "$CLI" "$P" --розгорнути "$projection" "$TMP/$projection.sens" \
    >"$TMP/$projection.back.txt" 2>"$TMP/$projection.reverse.err"
  test ! -s "$TMP/$projection.reverse.err"
  cmp "$input" "$TMP/$projection.back.txt"
  timeout 15s "$CLI" "$P" --пакувати "$projection" "$TMP/$projection.back.txt" \
    >"$TMP/$projection.again.sens"
  cmp "$TMP/$projection.sens" "$TMP/$projection.again.sens"
  OK=$((OK+1))
done
test "$OK" -eq 5
# Цитовані D7 дужки — текстові дані, не D2 структура.
printf '"("\n")"\n' >"$TMP/brackets.txt"
timeout 15s "$CLI" "$P" --пакувати укр "$TMP/brackets.txt" \
  >"$TMP/brackets.sens"
timeout 15s "$CLI" "$P" --розгорнути укр "$TMP/brackets.sens" \
  >"$TMP/brackets.back.txt"
cmp "$TMP/brackets.txt" "$TMP/brackets.back.txt"

# Відмова обов'язково перед першим байтом stdout.
NEG=0
reject() {
  if timeout 15s "$CLI" "$@" >"$TMP/no-out" 2>"$TMP/rejected.err"; then
    echo "РЯДКИ-Д7-ПРОВАЛ: прийнято $*" >&2; exit 1
  fi
  test ! -s "$TMP/no-out" || {
    echo "РЯДКИ-Д7-ПРОВАЛ: частковий stdout $*" >&2; exit 1;
  }
  grep -Fq 'РЯДКИ-Д7-ВІДМОВА' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
printf '()\n' >"$TMP/empty.txt"
reject "$P" --пакувати LISP "$TMP/empty.txt"
reject "$P" --пакувати укр "$TMP/empty.txt"
printf 'б\nНЕМАЄ\n' >"$TMP/late.txt"
reject "$P" --пакувати укр "$TMP/late.txt"
printf 'б' >"$TMP/no-final.txt"
reject "$P" --пакувати укр "$TMP/no-final.txt"
printf 'б\n\n' >"$TMP/blank.txt"
reject "$P" --пакувати укр "$TMP/blank.txt"
printf '\377\n' >"$TMP/utf8.txt"
reject "$P" --пакувати укр "$TMP/utf8.txt"
cp "$TMP/uk.txt" "$TMP/false.lisp"
reject "$P" --пакувати укр "$TMP/false.lisp"
reject "$P" --пакувати хибна "$TMP/uk.txt"
reject "$P" --помилка укр "$TMP/uk.txt"
printf '\363' >"$TMP/broken.sens"
reject "$P" --розгорнути укр "$TMP/broken.sens"
printf '0101100 0010110\n' >"$TMP/syn.words"
timeout 15s bash ./scripts/test-t5m-cli.sh >"$TMP/t5m-regression.log" 2>&1
mkdir -p "$TMP/t5m-units" "$TMP/t5m-bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -Fu"$ROOT/src" \
  -FU"$TMP/t5m-units" -FE"$TMP/t5m-bin" -osenst5m \
  "$ROOT/src/senst5m.lpr" >"$TMP/t5m-build.log" 2>&1 || {
    cat "$TMP/t5m-build.log" >&2; exit 1;
  }
timeout 15s "$TMP/t5m-bin/senst5m" --пакувати-слова "$TMP/syn.words" \
  >"$TMP/syn.sens"
reject "$P" --розгорнути укр "$TMP/syn.sens"
printf '0101100 000000000000\n' >"$TMP/d12.words"
timeout 15s "$TMP/t5m-bin/senst5m" --пакувати-слова "$TMP/d12.words" \
  >"$TMP/d12.sens"
reject "$P" --розгорнути укр "$TMP/d12.sens"
# Незалежний pinned D7 може в інших поверхнях мати колізію.
# Намірено мутуємо ЛИШЕ en таблицю у тимчасовому дереві, не репозиторій.
mkdir -p "$TMP/mutant/lib/domains"
cp external/sens/lib/domains/d{1..10}.lisp "$TMP/mutant/lib/domains/"
python3 - "$TMP/mutant/lib/domains/d7.lisp" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
assert "(en v)" in s and "(en w)" in s
p.write_text(s.replace("(en w)", "(en v)", 1), encoding="utf-8")
PY
printf 'v\n' >"$TMP/ambiguous.txt"
reject "$TMP/mutant" --пакувати en "$TMP/ambiguous.txt"
# Після відмов жоден каталог/глобальне середовище не отруєно.
timeout 15s "$CLI" "$P" --пакувати en "$TMP/en.txt" \
  >"$TMP/recovered.sens"
cmp "$TMP/expected.sens" "$TMP/recovered.sens"
# G1.47: граничні 8192 pinned W7, один owned UTF-8 буфер для експорту.
# Це транспорт ДАНИХ, не парсер програми й не арифметика D12+.
python3 - "$TMP" <<'PY'
from pathlib import Path
import importlib.util
import sys
root = Path(sys.argv[1])
token = "б\n".encode("utf-8")
(root / "граничні.txt").write_bytes(token * 8192)
(root / "зайвий-рядок.txt").write_bytes(token * 8193)
(root / "пізній-неправильний.txt").write_bytes(token * 8191 + "НЕМАЄ\n".encode("utf-8"))
source = root / "pinned-codec.py"
spec = importlib.util.spec_from_file_location("pinned_t5m_limit", source)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
physical = module.encode_t5m_projection(" ".join(["0101100"] * 8193))
assert module.decode_t5m_bytes(physical) == ["0101100"] * 8193
(root / "зайве-фізичне.sens").write_bytes(physical)
PY
timeout 20s "$CLI" "$P" --пакувати укр "$TMP/граничні.txt" \
  >"$TMP/граничні.sens" 2>"$TMP/граничні.err"
test ! -s "$TMP/граничні.err"
timeout 20s "$CLI" "$P" --розгорнути укр "$TMP/граничні.sens" \
  >"$TMP/граничні-відновлені.txt" 2>"$TMP/граничні-розгортання.err"
test ! -s "$TMP/граничні-розгортання.err"
cmp "$TMP/граничні.txt" "$TMP/граничні-відновлені.txt"
timeout 20s "$CLI" "$P" --пакувати укр "$TMP/граничні-відновлені.txt" \
  >"$TMP/граничні-вдруге.sens"
cmp "$TMP/граничні.sens" "$TMP/граничні-вдруге.sens"
reject "$P" --пакувати укр "$TMP/зайвий-рядок.txt"
reject "$P" --пакувати укр "$TMP/пізній-неправильний.txt"
reject "$P" --розгорнути укр "$TMP/зайве-фізичне.sens"
echo "РЯДКИ-Д7-ГАРАЗД pinned=$PIN surface-roundtrip=$OK negatives=$NEG quoted-D7=так upstream-T5M=байт-у-байт recovery=так граничні-W7=8192 зайві-W7=відмова"
