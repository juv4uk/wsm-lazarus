#!/usr/bin/env bash
# G3.49: реальний FPC + Lazarus/GTK2/Xvfb, один Core1-сеанс у дочірньому PID.
set -euo pipefail
export LANG=C.UTF-8
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for name in fpc lazbuild xvfb-run timeout python3; do
  command -v "$name" >/dev/null || {
    echo "ЛКЛ-CORE1-СЕАНС-БЛОК: відсутній $name" >&2
    exit 127
  }
done
timeout 120s bash scripts/check-pin.sh
test -s external/sens/lib/core1.sens
test -s external/sens/lib/core1.lisp
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then for file in "$TMP"/*.log "$TMP"/*.err; do if [[ -s "$file" ]]; then echo "--- $file" >&2; tail -35 "$file" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-seans" "$TMP/units-fixture" build/lcl/bin
# Обидва FPC бінарники — справжні, жодного Python-коду замість runtime.
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-seans" -FE"$TMP/bin" \
  -osenscore1seans "$ROOT/src/senscore1seans.lpr" \
  >"$TMP/fpc-seans.log" 2>&1 || { cat "$TMP/fpc-seans.log" >&2; exit 1; }
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-fixture" -FE"$TMP/bin" \
  -otest-core1-paket "$ROOT/scripts/test-core1-paket.pas" \
  >"$TMP/fpc-fixture.log" 2>&1 || { cat "$TMP/fpc-fixture.log" >&2; exit 1; }
timeout 90s "$TMP/bin/test-core1-paket" "$ROOT/external/sens" "$ROOT" "$TMP" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'CORE1-PAKET-FIXTURES-OK' "$TMP/fixtures.log"
# Перевірка незалежних відповідей існуючого host-каналу перед GUI.
timeout 120s python3 scripts/test-core1-seans.py "$TMP/bin/senscore1seans" \
  "$ROOT" "$TMP" >"$TMP/host-baseline.log" 2>"$TMP/host-baseline.err"
grep -Fq 'CORE1-СЕАНС-ГАРАЗД' "$TMP/host-baseline.log"
# Фізичний запуск Lazarus, а не лише компіляція GUI без графічного вводу.
timeout 180s lazbuild --widgetset=gtk2 --build-all gui/sens-core1-seans-okno.lpi \
  >"$TMP/lazarus.log" 2>&1 || { tail -120 "$TMP/lazarus.log" >&2; exit 1; }
GUI="$ROOT/build/lcl/bin/sens-core1-seans-okno"
test -x "$GUI"
timeout --signal=TERM --kill-after=5s 150s xvfb-run -a -s \
  '-screen 0 1200x850x24' "$GUI" \
  --самоперевірка "$ROOT" "$TMP" "$TMP/bin/senscore1seans" \
  >"$TMP/lcl.out" 2>"$TMP/lcl.err" || {
    cat "$TMP/lcl.out" "$TMP/lcl.err" >&2
    echo 'ЛКЛ-CORE1-СЕАНС-БЛОК: не пройдені живі GTK2 кліки' >&2
    exit 1
  }
cat "$TMP/lcl.out"
grep -Fq 'ЛКЛ-CORE1-СЕАНС-ГАРАЗД GTK2=так FPC=справжній' "$TMP/lcl.out"
grep -Fq 'кліки=9 успіхи=5 відмови=4 remote-відмови=3' "$TMP/lcl.out"
grep -Fq 'pid=незмінний physical-T5M=побайтово' "$TMP/lcl.out"
grep -Fq 'відновлення=так stale=очищено' "$TMP/lcl.out"
grep -Fq 'REPL=НЕ-ПОВНИЙ GC=НЕ-ІНТЕГРОВАНО' "$TMP/lcl.out"
if grep -Eq '(^|[^0-9])([1-9][0-9]*) unfreed memory blocks' "$TMP/lcl.err"; then
  cat "$TMP/lcl.err" >&2
  echo 'ЛКЛ-CORE1-СЕАНС-БЛОК: витік пам’яті' >&2
  exit 1
fi
echo 'ЛКЛ-CORE1-СЕАНС-CI-ГАРАЗД pinned=Contract12 FPC=реальний GTK2=Xvfb'
