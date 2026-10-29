#!/usr/bin/env bash
# G8 / #712: реальний design-time IDEIntf пакет + те саме LCL вікно.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in lazbuild fpc xvfb-run timeout grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "SENS-IDE-БЛОКЕР: бракує $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rc=$?; if (( rc != 0 )); then echo "SENS-IDE-ЗБІЙ: rc=$rc" >&2; for x in "$TMP"/*.log; do if [[ -f "$x" ]]; then tail -n 60 "$x" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p build/ide-map/bin build/ide-map/units "$TMP/fake/gui"
printf '# Штучний корінь (тільки для негативного тесту)\n' >"$TMP/fake/AGENTS.md"
printf 'невірний LPI\n' >"$TMP/fake/gui/sens-inspector.lpi"
timeout 300s lazbuild --ws=gtk2 -B ide/sens_ide_map.lpk   >"$TMP/package.log" 2>&1 || { cat "$TMP/package.log" >&2; exit 1; }
grep -Eiq 'compiled|success|Зібран|0 errors|0 error' "$TMP/package.log" || {
  cat "$TMP/package.log" >&2; exit 1;
}
timeout 300s lazbuild --ws=gtk2 -B scripts/test-sens-ide-map.lpi   >"$TMP/testbuild.log" 2>&1 || { cat "$TMP/testbuild.log" >&2; exit 1; }
test -x build/ide-map/bin/test-sens-ide-map
SENS_REPO_ROOT="$ROOT" timeout 90s xvfb-run -a   build/ide-map/bin/test-sens-ide-map "$ROOT" "$TMP/absent"   >"$TMP/ui.log" 2>"$TMP/ui.err"
grep -Fq 'SENS-LAZARUS-IDE-МАПА-ГАРАЗД:' "$TMP/ui.log"
if grep -Fq 'unfreed memory blocks' "$TMP/ui.err"; then
  grep -Fq '0 unfreed memory blocks' "$TMP/ui.err"
fi
echo "SENS-IDE-ГАРАЗД: lazbuild=IDEIntf+LCL GTK2/Xvfb=так без=семантичного-дублювання; IDE-встановлення=не-перевірено"
