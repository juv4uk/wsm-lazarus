#!/usr/bin/env bash
# Справжній Lazarus/LCL GTK2 огляд фізичних байтів без мовної семантики.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'БАЙТИ-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'БАЙТИ-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
mkdir -p build/lcl-bait-ogliad/bin build/lcl-bait-ogliad/units
lazbuild --widgetset=gtk2 --build-all gui/sens-bait-ogliad.lpi
BIN="$ROOT/build/lcl-bait-ogliad/bin/sens-bait-ogliad"
[[ -x "$BIN" ]] || { echo 'БАЙТИ-БЛОКЕР: файл Lazarus не зібрано' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Шість exact binary words, фізичні 4 байти; розмітка T5M вже перевірена існуючим кодом.
python3 - "$TMP" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
words = ["10", "111", "0", "1", "00", "11"]
trits = "2".join(words)
trits += "2" * (-len(trits) % 5)
physical = bytes(sum(int(t) * (3 ** (4-i)) for i,t in enumerate(trits[j:j+5])) for j in range(0,len(trits),5))
assert len(physical) == 4, (physical, trits)
(p / "добрий.sens").write_bytes(physical)
(p / "хибний.sens").write_bytes(b"\xf3")
(p / "порожній.sens").write_bytes(b"")
PY
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$TMP/добрий.sens" "$TMP/хибний.sens" "$TMP/порожній.sens" \
  > "$TMP/звіт" 2> "$TMP/помилки"
test ! -s "$TMP/помилки"
grep -F 'LCL-БАЙТИ-АДРЕСИ-ГАРАЗД' "$TMP/звіт"
grep -F 'LCL-БАЙТИ-ГАРАЗД' "$TMP/звіт"
echo 'LCL-БАЙТИ-ЗБІРКА-ГАРАЗД Lazarus=реальний'
