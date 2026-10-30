#!/usr/bin/env bash
# G6.114 — реальна LCL/GTK2 компіляція .sens → WideIR → ELF64.
# Не створює мовного закону та не виконує недовірений ELF в GUI.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in timeout fpc lazbuild xvfb-run git cmp readelf mktemp; do
  command -v "$tool" >/dev/null || {
    echo "ЛАЗАРУС-КОМПІЛЯТОР-БЛОК: немає $tool" >&2
    exit 127
  }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
mkdir -p build/lcl-ostacha/bin build/lcl-ostacha/units
TMP="$(mktemp -d)"
trap 'rc=$?; if (( rc != 0 )); then for f in "$TMP"/*.log "$TMP"/*.err; do
  [[ ! -f "$f" ]] || { echo "--- $f" >&2; tail -n 50 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
# Однакові canonical packed fixtures для LCL та headless compiler.
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-irwiderest "$ROOT/scripts/test-irwiderest.pas" \
  >"$TMP/fixtures-build.log" 2>&1 || {
    cat "$TMP/fixtures-build.log" >&2; exit 1;
  }
timeout 30s "$TMP/bin/test-irwiderest" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'G6.102-REST-FIXTURES-OK cases=28' "$TMP/fixtures.log"
timeout 300s lazbuild --widgetset=gtk2 --build-all \
  gui/sens-ostacha-compiler.lpi >"$TMP/lazarus-build.log" 2>&1 || {
    cat "$TMP/lazarus-build.log" >&2; exit 1;
  }
GUI="$ROOT/build/lcl-ostacha/bin/sens-ostacha-compiler"
test -x "$GUI"
printf '(остача 7 3)\n' >"$TMP/проєкція.lisp"
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 90s \
  xvfb-run -a -s '-screen 0 1400x950x24' "$GUI" --самоперевірка \
  "$TMP/physical/04.sens" "$TMP/physical/18.sens" \
  "$TMP/physical/bad-t5m.sens" "$TMP/проєкція.lisp" \
  "$TMP/physical/div-zero.sens" "$TMP/перевірений.elf" \
  >"$TMP/gui.log" 2>"$TMP/gui.err" || {
    cat "$TMP/gui.log" "$TMP/gui.err" >&2; exit 1;
  }
test ! -s "$TMP/gui.err"
grep -Fq 'ЛАЗАРУС-ОСТАЧА-ГОТОВО GTK2=так IR=4 ELF=справжній' "$TMP/gui.log"
for row in '04 перевірений.elf' '18 перевірений.elf.signed.elf'; do
  read -r case_id binary <<<"$row"
  test -x "$TMP/$binary"
  timeout 5s readelf -h "$TMP/$binary" >"$TMP/$case_id.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$case_id.header"
  timeout 5s "$TMP/$binary" >"$TMP/$case_id.output.sens" \
    2>"$TMP/$case_id.machine.err"
  test ! -s "$TMP/$case_id.machine.err"
  cmp "$TMP/$case_id.output.sens" \
      "$TMP/physical/$case_id.expected.sens"
done
test ! -e "$TMP/перевірений.elf-після-відмови.elf"
# Наскрізні 28/27 відмови та signed pinned межі НЕ послаблюємо.
timeout 300s bash scripts/test-irwiderest.sh \
  >"$TMP/native-regression.log" 2>"$TMP/native-regression.err" || {
    cat "$TMP/native-regression.log" "$TMP/native-regression.err" >&2; exit 1;
  }
grep -Fq 'native-elf=28 negatives=27' "$TMP/native-regression.log"
echo 'ЛАЗАРУС-КОМПІЛЯТОР-ПЕРЕВІРЕНО GTK2=так ELF-запусків=2 signed=так D12=точно no-clobber=так native=28/27 energy=NOT-MEASURED'
