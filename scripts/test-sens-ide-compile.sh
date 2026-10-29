#!/usr/bin/env bash
# G8.2 — тест IDEIntf-команди, яка реально викликає вже допущений компілятор.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SENS-IDE-КОМПІЛЯТОР-БЛОК: потрібний Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc lazbuild xvfb-run cmp readelf mktemp git; do
  command -v "$tool" >/dev/null || {
    echo "SENS-IDE-КОМПІЛЯТОР-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 240s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc != 0)); then
    echo "SENS-IDE-КОМПІЛЯТОР-ПОМИЛКА rc=$rc" >&2
    for x in "$TMP"/*.log "$TMP"/*.err; do
      if [[ -s "$x" ]]; then echo "--- $x" >&2;tail -n 70 "$x" >&2;fi
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap finish EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/sub" "$TMP/nsd"
mkdir -p build/ide-compile/bin build/ide-compile/units
for row in \
  'scripts/test-irwidesub.pas:test-irwidesub' \
  'scripts/test-irwidensd.pas:test-irwidensd' \
  'src/senswidefrontelf.lpr:senswidefrontelf'; do
  IFS=: read -r source binary <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build.log" 2>&1 || {
      cat "$TMP/$binary.build.log" >&2;exit 1; }
done
timeout 30s "$TMP/bin/test-irwidesub" "$TMP/sub" >"$TMP/sub.log"
timeout 30s "$TMP/bin/test-irwidensd" "$TMP/nsd" >"$TMP/nsd.log"
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/sub.log"
grep -Fq 'G6.105-NSD-FIXTURES-OK cases=14' "$TMP/nsd.log"
timeout 420s lazbuild --ws=gtk2 -B ide/sens_ide_map.lpk \
  >"$TMP/pkg.log" 2>&1 || { cat "$TMP/pkg.log" >&2;exit 1; }
timeout 360s lazbuild --ws=gtk2 -B scripts/test-sens-ide-compile.lpi \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2;exit 1; }
test -x build/ide-compile/bin/test-sens-ide-compile
printf '(відняти 7 3)\n' > "$TMP/проєкція.lisp"
TMPDIR="$TMP" SENS_REPO_ROOT="$ROOT" LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 120s \
  xvfb-run -a -s '-screen 0 1280x880x24' \
  build/ide-compile/bin/test-sens-ide-compile \
  "$ROOT" "$TMP/sub/02.sens" "$TMP/nsd/01.sens" \
  "$TMP/nsd/bad-t5m.sens" "$TMP/проєкція.lisp" \
  "$TMP/nsd/other-d7.sens" "$TMP/ide" \
  >"$TMP/ui.log" 2>"$TMP/ui.err" || {
    cat "$TMP/ui.log" "$TMP/ui.err" >&2;exit 1; }
grep -Fq 'SENS-LAZARUS-IDE-КОМПІЛЯТОР-ГАРАЗД:' "$TMP/ui.log"
grep -Fq 'native=3 T5M=exact no-stale=так' "$TMP/ui.log"
# Кожен нативний виклик уже звільнив приватний ELF і каталог.
test -z "$(find "$TMP" -maxdepth 1 -type d -name 'sens-native-*' -print -quit)"
test ! -e "$TMP/ide-after.elf"
cmp "$TMP/ide-sub.elf" "$TMP/sub/02.reference.elf"
cmp "$TMP/ide-sub.elf" "$TMP/ide-recovery.elf"
for row in 'sub sub/02' 'nsd nsd/01'; do
  read -r profile fixture <<< "$row"
  timeout 25s "$TMP/bin/senswidefrontelf" \
    --скомпілювати-фізичну-форму "$TMP/$fixture.sens" \
    "$TMP/$profile-reference.elf" >"$TMP/$profile-reference.log"
  cmp "$TMP/ide-$profile.elf" "$TMP/$profile-reference.elf"
  timeout 5s readelf -h "$TMP/ide-$profile.elf" >"$TMP/$profile-elf.log"
  grep -Eq 'Type:.*DYN' "$TMP/$profile-elf.log"
  timeout 5s "$TMP/ide-$profile.elf" >"$TMP/$profile.actual.sens"
  cmp "$TMP/$profile.actual.sens" "$TMP/$fixture.expected.sens"
done
test "$(wc -c < "$TMP/sub.actual.sens")" -eq 5
test "$(wc -c < "$TMP/nsd.actual.sens")" -eq 3
timeout 900s bash scripts/test-irwidefront-8.sh \
  >"$TMP/legacy.log" 2>"$TMP/legacy.err" || {
    tail -n 70 "$TMP/legacy.err" >&2;exit 1; }
grep -Fq 'ВІСІМ-ПРОФІЛІВ-ГОТОВО:' "$TMP/legacy.log"
timeout 360s bash scripts/test-sens-ide-map.sh >"$TMP/map.log" 2>"$TMP/map.err"
grep -Fq 'SENS-IDE-ГАРАЗД:' "$TMP/map.log"
timeout 90s bash scripts/check-no-lcl.sh >"$TMP/no-lcl.log"
echo 'SENS-IDE-КОМПІЛЯТОР-ПЕРЕВІРЕНО pinned=так IDEIntf=так GTK2=так compiled=2 ELF-executed=2 IDE-native-run=3 IDE-T5M=exact byte-identical=так negative=5 recovery=так oldIDE=так regression=8 energy=NOT-MEASURED'
