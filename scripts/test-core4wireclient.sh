#!/usr/bin/env bash
# G5.30 — реальний довгоживучий FPC client до pinned binary Core4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'D7-КЛІЄНТ-БЛОКЕР: потрібен FPC' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'D7-КЛІЄНТ-БЛОКЕР: потрібен timeout' >&2; exit 127; }
# Старі G5.23/G5.26/G5.28 фізичні позитиви/негативи не вимикаємо.
timeout 120s bash ./scripts/test-core4kanal.sh
BIN="$ROOT/build/m0.2/bin"
UNITS="$ROOT/build/m0.2/core4-wireclient-units"
mkdir -p "$BIN" "$UNITS"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" "$ROOT/scripts/test-core4wireclient.pas"
test -x "$BIN/test-core4wireclient"
test -x "$BIN/senscore4kanal"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! timeout 80s "$BIN/test-core4wireclient" "$ROOT" "$BIN/senscore4kanal" \
  >"$TMP/report" 2>"$TMP/errors"; then
  echo 'D7-КЛІЄНТ-ПОМИЛКА: end-to-end фізичний канал' >&2
  cat "$TMP/report" >&2
  cat "$TMP/errors" >&2
  exit 1
fi
cat "$TMP/report"
cat "$TMP/errors" >&2
grep -Fq 'D7-КЛІЄНТ-ГАРАЗД pinned=core4.sens визначень=3 колізії=ні exact-D7=так' "$TMP/report"
grep -Fq 'один-PID=так пакет=3 відновлення=так REPL=ні' "$TMP/report"
if [[ -s "$TMP/errors" ]]; then
  grep -Fq '0 unfreed memory blocks' "$TMP/errors"
fi
echo 'D7-КЛІЄНТ-CI-ГАРАЗД FPC=справжній процес=постійний transport=T5M D7=повний колізії=ні'
