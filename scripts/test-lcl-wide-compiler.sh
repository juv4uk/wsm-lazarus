#!/usr/bin/env bash
# G6 — справжній Lazarus/LCL над уже перевіреним спільним WideIR.
# Не новий compiler, не мовний закон, не замір джоулів.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'LCL-WIDE-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for tool in timeout fpc lazbuild xvfb-run git cmp readelf mktemp; do
  command -v "$tool" >/dev/null || {
    echo "LCL-WIDE-БЛОК: немає $tool" >&2; exit 127; }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc != 0)); then
    echo "LCL-WIDE-ПОМИЛКА rc=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 70 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap finish EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/sub" "$TMP/nsd"
mkdir -p build/lcl-wide/bin build/lcl-wide/units
for row in \
  'scripts/test-irwidesub.pas:test-irwidesub' \
  'scripts/test-irwidensd.pas:test-irwidensd' \
  'src/senswidensdelf.lpr:senswidensdelf' \
  'src/senswidefrontelf.lpr:senswidefrontelf'; do
  IFS=: read -r source binary <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build.log" 2>&1 || {
      cat "$TMP/$binary.build.log" >&2; exit 1; }
  test -x "$TMP/bin/$binary"
done
HEAPTRC="log=$TMP/sub.heap" timeout 30s "$TMP/bin/test-irwidesub" "$TMP/sub" \
  >"$TMP/sub.log" 2>"$TMP/sub.err"
HEAPTRC="log=$TMP/nsd.heap" timeout 30s "$TMP/bin/test-irwidensd" "$TMP/nsd" \
  >"$TMP/nsd.log" 2>"$TMP/nsd.err"
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/sub.log"
grep -Fq 'G6.105-NSD-FIXTURES-OK cases=14' "$TMP/nsd.log"
for heap in "$TMP/sub.heap" "$TMP/nsd.heap"; do
  if [[ -s "$heap" ]]; then
    grep -Fq '0 unfreed memory blocks' "$heap"
  fi
done
timeout 360s lazbuild --widgetset=gtk2 --build-all \
  gui/sens-wide-compiler.lpi >"$TMP/lazbuild.log" 2>&1 || {
    cat "$TMP/lazbuild.log" >&2; exit 1; }
GUI="$ROOT/build/lcl-wide/bin/sens-wide-compiler"
test -x "$GUI"
printf '(відняти 1 -2048)\n' > "$TMP/людська-проєкція.lisp"
TMPDIR="$TMP" LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 100s \
  xvfb-run -a -s '-screen 0 1400x950x24' "$GUI" --самоперевірка \
    "$TMP/sub/02.sens" "$TMP/nsd/01.sens" \
    "$TMP/nsd/bad-t5m.sens" "$TMP/людська-проєкція.lisp" \
    "$TMP/nsd/negative-left.sens" "$TMP/gui" \
    >"$TMP/gui.log" 2>"$TMP/gui.err" || {
      cat "$TMP/gui.log" "$TMP/gui.err" >&2; exit 1; }
test ! -s "$TMP/gui.err"
grep -Fq 'ЛАЗАРУС-СПІЛЬНИЙ-ГОТОВО GTK2=так WideIR=4' "$TMP/gui.log"
grep -Fq 'виконання=3 T5M=exact' "$TMP/gui.log"
# Три native виклики створили приватні mkdtemp, але жодного не залишили.
test -z "$(find "$TMP" -maxdepth 1 -name 'sens-native-*' -print -quit)"
test ! -e "$TMP/gui-after-error.elf"
# Незалежне порівняння з існуючими спеціалізованим і єдиним CLI.
timeout 30s "$TMP/bin/senswidensdelf" --скомпілювати-D6-нсд-D12 \
  "$TMP/nsd/01.sens" "$TMP/nsd-special.elf" >"$TMP/nsd-special.log"
cmp "$TMP/gui-sub.elf" "$TMP/sub/02.reference.elf"
cmp "$TMP/gui-nsd.elf" "$TMP/nsd-special.elf"
for row in 'sub sub/02' 'nsd nsd/01'; do
  read -r profile fixture <<< "$row"
  timeout 30s "$TMP/bin/senswidefrontelf" \
    --скомпілювати-фізичну-форму "$TMP/$fixture.sens" \
    "$TMP/$profile-unified.elf" >"$TMP/$profile-unified.log"
  cmp "$TMP/gui-$profile.elf" "$TMP/$profile-unified.elf"
  test -x "$TMP/gui-$profile.elf"
  readelf -h "$TMP/gui-$profile.elf" >"$TMP/$profile.header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$profile.header.log"
  timeout 5s "$TMP/gui-$profile.elf" >"$TMP/$profile.actual.sens" \
    2>"$TMP/$profile.machine.err"
  test ! -s "$TMP/$profile.machine.err"
  cmp "$TMP/$profile.actual.sens" "$TMP/$fixture.expected.sens"
done
test "$(wc -c < "$TMP/sub.actual.sens")" -eq 5
test "$(wc -c < "$TMP/nsd.actual.sens")" -eq 3
# Регресія всіх інших 6 профілів, не лише компіляція LCL.
timeout 900s bash scripts/test-irwidefront-8.sh \
  >"$TMP/regression.log" 2>"$TMP/regression.err" || {
    tail -n 70 "$TMP/regression.err" >&2;exit 1; }
grep -Fq 'ВІСІМ-ПРОФІЛІВ-ГОТОВО:' "$TMP/regression.log"
# Guard обов'язковий і НЕ змінений. Ставимо після доказу GUI,
# щоб окремий чужий false positive не приховував результат збірки.
timeout 120s bash scripts/check-no-lcl.sh
echo 'ЛАЗАРУС-СПІЛЬНИЙ-ПЕРЕВІРЕНО GTK2=так фізичних=2 ELF=2 виконання=3 T5M=exact pinned-D5-D6=так D24=так no-clobber=так regression=8 energy=NOT-MEASURED'
