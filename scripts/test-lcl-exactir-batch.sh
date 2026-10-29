#!/usr/bin/env bash
# G3.16 — справжній Lazarus/GTK2 пакет фізичних незалежних D3 форм.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ПАКЕТ-D3-БЛОК: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ПАКЕТ-D3-БЛОК: немає Xvfb' >&2; exit 127; }
./scripts/check-pin.sh
bash ./scripts/test-d3batch.sh
bash ./scripts/test-lcl-exactir-d3.sh
BIN="$ROOT/build/m0.2/bin/senst5m"
GUI="$ROOT/build/lcl-exactir/bin/exactir-inspector"
test -x "$BIN" && test -x "$GUI"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '0 00 10 001 000 01 00 10 111 1 0 01 10 001 111111111 01\n' > "$TMP/пакет.words"
printf '0 000 10 1 11 0 01 111111111\n' > "$TMP/відповідь.words"
printf '0 10 001 1 0 01\n' > "$TMP/пізній-збій.words"
for item in пакет відповідь пізній-збій; do
  "$BIN" --пакувати-слова "$TMP/$item.words" > "$TMP/$item.sens"
done
for _ in $(seq 1 65); do printf '0 '; done > "$TMP/65.words"
printf '\n' >> "$TMP/65.words"
"$BIN" --пакувати-слова "$TMP/65.words" > "$TMP/65.sens"
printf '\363' > "$TMP/зіпсовано.sens"
LC_ALL=C.UTF-8 xvfb-run -a "$GUI" --самоперевірка-пакета \
  "$TMP/пакет.sens" "$TMP/відповідь.sens" \
  "$TMP/пізній-збій.sens" "$TMP/65.sens" "$TMP/зіпсовано.sens" \
  | tee "$TMP/свідчення"
grep -Fq 'LCL-ПАКЕТ-D3-ГАРАЗД' "$TMP/свідчення"
echo 'LCL-ПАКЕТ-D3-ФІЗИЧНИЙ-ДОКАЗ-ГАРАЗД T5M=побайтовий'
