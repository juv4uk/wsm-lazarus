#!/usr/bin/env bash
# G3.43 — справжній Lazarus/GTK2 GUI над єдиним живим Core1 runtime.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for cmd in fpc lazbuild xvfb-run timeout; do
  command -v "$cmd" >/dev/null || { echo "БЛОК: немає $cmd" >&2; exit 127; }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test -s external/sens/lib/core1.sens
test -s external/sens/lib/core1.lisp
mkdir -p build/lcl/bin build/lcl/core1-pershe-units

# Незалежний SENS oracle перевіряє реальний виклик із того самого
# pinned визначення; жодного перепису DEFINE на Pascal або в GUI.
bash scripts/test-core1-first.sh

lazbuild --widgetset=gtk2 --build-all gui/sens-core1-pershe-okno.lpi
GUI="$ROOT/build/lcl/bin/sens-core1-pershe-okno"
test -x "$GUI"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Symlink must never be overwritten even if its target is a valid .sens.
ln -s core1-export-0.sens "$TMP/core1-existing-symlink.sens"
if ! LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 120s \
  xvfb-run -a -s '-screen 0 1200x850x24' "$GUI" \
    --самоперевірка "$ROOT/external/sens" "$ROOT" "$TMP" \
    >"$TMP/вивід" 2>"$TMP/діагностика"; then
  cat "$TMP/вивід" "$TMP/діагностика" >&2
  echo 'ЛКЛ-ПЕРШИЙ-CORE1-БЛОК: реальні кліки/фізичні відповіді' >&2
  exit 1
fi
cat "$TMP/вивід"
if grep -Eq '(^|[^0-9])([1-9][0-9]*) unfreed memory blocks' "$TMP/діагностика"; then
  cat "$TMP/діагностика" >&2
  echo 'ЛКЛ-ПЕРШИЙ-CORE1-БЛОК: витік пам’яті' >&2
  exit 1
fi
grep -Fq 'ЛКЛ-ПЕРШИЙ-CORE1-ГАРАЗД GTK2=так FPC=справжній' "$TMP/вивід"
grep -Fq 'виклики=9 D1:0=так D1:1=так W24=opaque' "$TMP/вивід"
grep -Fq 'після-помилки=відновлено runtime=той-самий' "$TMP/вивід"
grep -Fq 'редагування-шляху=очищено' "$TMP/вивід"
grep -Fq 'експорт=байт-в-байт no-clobber=так W24=точний' "$TMP/вивід"
test -s "$TMP/core1-export-0.sens" && test -s "$TMP/core1-export-w24.sens"
test -L "$TMP/core1-existing-symlink.sens"
test ! -e "$TMP/core1-projection.lisp"
test ! -e "$TMP/core1-stale.sens"
test ! -e "$TMP/core1-bad-export.sens"
test "$(stat -c '%a' "$TMP/core1-export-0.sens")" = 600
test "$(stat -c '%a' "$TMP/core1-export-w24.sens")" = 600
grep -Fq 'GC=НЕ-ІНТЕГРОВАНО REPL=НЕ-ПОВНИЙ' "$TMP/вивід"
echo 'ЛКЛ-ПЕРШИЙ-CORE1-ЗБІРКА-ГАРАЗД FPC=3.2.x Lazarus=GTK2 Xvfb=так SENS-оракул=так'
