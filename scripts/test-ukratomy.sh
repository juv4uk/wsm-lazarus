#!/usr/bin/env bash
# G2.50: справжній FPC, pinned укр, exact domain і негативи без stdout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'УКР-АТОМИ-БЛОКЕР: FPC відсутній' >&2; exit 127; }
mkdir -p build/m0.2/ukratomy/units build/m0.2/ukratomy/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/ukratomy/units" \
  -FE"$ROOT/build/m0.2/ukratomy/bin" \
  -osensukratomy src/sensukratomy.lpr
BIN="$ROOT/build/m0.2/ukratomy/bin/sensukratomy"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 20s "$BIN" --самоперевірка >"$TMP/self"
grep -Fq 'УКР-АТОМИ-САМОПЕРЕВІРКА-ГАРАЗД' "$TMP/self"
cat >"$TMP/вхід.lisp" <<'LISP'
порожній?
(як-є "і" ())
невідоме-ім'я
LISP
timeout 20s "$BIN" "$TMP/вхід.lisp" >"$TMP/out"
grep -Fq 'координата=D4:0101' "$TMP/out"
grep -Fq 'координата=D3:001' "$TMP/out"
grep -Fq "незв’язаний=невідоме-ім'я" "$TMP/out"
grep -Fq 'зв’язаних=2 незв’язаних=1' "$TMP/out"
grep -Fq 'викличність=не-перевірено D7=дані D12+=не-зв’язуємо' "$TMP/out"
test "$(wc -l <"$TMP/out")" -eq 4
printf 'порожнє?\n' >"$TMP/коротка.lisp"
timeout 20s "$BIN" "$TMP/коротка.lisp" >"$TMP/out"
grep -Fq 'зв’язаних=0 незв’язаних=1' "$TMP/out"
printf '(")" ())\n' >"$TMP/рядок.lisp"
timeout 20s "$BIN" "$TMP/рядок.lisp" >"$TMP/out"
grep -Fq 'зв’язаних=0 незв’язаних=0' "$TMP/out"
reject() {
  local name="$1"; shift
  local code=0
  timeout 20s "$BIN" "$@" >"$TMP/out" 2>"$TMP/err" || code=$?
  if [[ "$code" -ne 2 ]] || [[ -s "$TMP/out" ]]; then
    echo "УКР-АТОМИ-ТЕСТ-ПОМИЛКА $name rc=$code" >&2
    exit 1
  fi
  grep -Fq 'УКР-АТОМИ-ПОМИЛКА' "$TMP/err"
}
cp "$TMP/вхід.lisp" "$TMP/не-програма.sens"
reject 'неявна .sens проєкція' "$TMP/не-програма.sens"
printf '("незакрите"\n' >"$TMP/злам.lisp"
reject 'незакритий список' "$TMP/злам.lisp"
printf '\300\257' >"$TMP/utf8.lisp"
reject 'некоректний UTF-8' "$TMP/utf8.lisp"
printf '\0' >"$TMP/nul.lisp"
reject 'NUL' "$TMP/nul.lisp"
: >"$TMP/порожньо.lisp"
reject 'порожній файл' "$TMP/порожньо.lisp"
reject 'відсутній файл' "$TMP/немає.lisp"
timeout 20s "$BIN" "$TMP/вхід.lisp" >"$TMP/recovery"
grep -Fq 'зв’язаних=2 незв’язаних=1' "$TMP/recovery"
echo 'УКР-АТОМИ-ТЕСТ-ГАРАЗД FPC=справжній D4=0101 D3=001 D7=дані негативи=6 відновлення=так'
