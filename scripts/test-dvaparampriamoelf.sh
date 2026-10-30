#!/usr/bin/env bash
# G6.182: один host FPC CLI → справжній ELF64 з двома runtime W24.
# Порівняння з раніше доведеним ДВОЕТАПНИМ машинним маршрутом;
# 16 реальних native виконань, опційний незалежний pinned SENS oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || exit 127
for tool in timeout git fpc cmp mktemp readelf grep wc python3 stat; do
  command -v "$tool" >/dev/null || { echo "ПРЯМО-D24-БЛОК: бракує $tool" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
MODE="${SENS_ORACLE_MODE:-native}"
case "$MODE" in
  native|full) ;;
  *) echo "ПРЯМО-D24-БЛОК: режим оракула" >&2; exit 2 ;;
esac
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "$MODE" = full ]]; then
  [[ -n "$ORACLE" && -x "$ORACLE" ]] || { echo "ПРЯМО-D24-БЛОК: немає oracle" >&2; exit 2; }
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "ПРЯМО-D24-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/u" "$TMP/bin" "$TMP/cases" "$TMP/n"
for spec in \
  'src/sensdvaparampriamoelf.lpr:sensdvaparampriamoelf' \
  'src/sensbodyfileelf.lpr:sensbodyfileelf' \
  'src/sensdvaparamstdinelf.lpr:sensdvaparamstdinelf' \
  'src/senschyslo.lpr:senschyslo' \
  'scripts/test-bodyfile-compiler.pas:test-bodyfile-compiler'; do
  IFS=: read -r source name <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 60s "$TMP/bin/test-bodyfile-compiler" "$ROOT" "$TMP/cases" \
  >"$TMP/manifest" 2>"$TMP/fixtures.err"
test "$(wc -l < "$TMP/manifest")" -eq 9
grep -Fq 'BODY-FILE-FIXTURES-OK cases=9 negatives=5' "$TMP/fixtures.err"
for op in add7 sub7; do
  root="$TMP/cases/$op"
  timeout 60s "$TMP/bin/sensdvaparampriamoelf" \
    --скомпілювати-два-D24-stdin "$root.body.sens" "$root.p1.sens" \
    "$root.p2.sens" "$TMP/$op.direct.elf" >"$TMP/$op.direct.log" 2>"$TMP/$op.err"
  test ! -s "$TMP/$op.err"
  grep -Fq 'result=D24-T5M' "$TMP/$op.direct.log"
  test "$(stat -c '%a' "$TMP/$op.direct.elf")" = 700
  # Доведений baseline, наявна в main двокрокова компіляція.
  timeout 60s "$TMP/bin/sensbodyfileelf" --два-D24-stdout \
    "$root.body.sens" "$root.p1.sens" "$root.p2.sens" \
    "$root.a1.sens" "$root.a2.sens" "$TMP/$op.static.elf" \
    >"$TMP/$op.static.log" 2>"$TMP/$op.static.err"
  test ! -s "$TMP/$op.static.err"
  timeout 60s "$TMP/bin/sensdvaparamstdinelf" --два-фізичні-D24-stdin \
    "$TMP/$op.static.elf" "$TMP/$op.two-stage.elf" \
    >"$TMP/$op.two-stage.log" 2>"$TMP/$op.two-stage.err"
  test ! -s "$TMP/$op.two-stage.err"
  cmp "$TMP/$op.direct.elf" "$TMP/$op.two-stage.elf"
  readelf -h "$TMP/$op.direct.elf" >"$TMP/$op.header"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$op.header"
  if readelf -l "$TMP/$op.direct.elf" | grep -Eq 'INTERP|DYNAMIC'; then
    echo "ПРЯМО-D24-ПРОВАЛ: не freestanding ELF" >&2; exit 1
  fi
  timeout 60s "$TMP/bin/sensdvaparampriamoelf" \
    --скомпілювати-два-D24-stdin "$root.body.sens" "$root.p1.sens" \
    "$root.p2.sens" "$TMP/$op.repeat.elf" >"$TMP/$op.repeat.log"
  cmp "$TMP/$op.direct.elf" "$TMP/$op.repeat.elf"
done
# Параметри — тільки тестові signed D24; результат обчислює native ELF.
cat >"$TMP/vectors" <<'VECTORS'
7 -3 4 10
-100 55 -45 -155
0 0 0 0
1000 50 1050 950
2047 0 2047 2047
-2048 0 -2048 -2048
-1 -1 -2 0
500 -500 0 1000
VECTORS
encode() {
  local value="$1" target="$2"
  printf '%s\n' "$value" >"$TMP/n/число.lisp"
  rm -f -- "$target"
  timeout 30s "$TMP/bin/senschyslo" --з-укр D24 \
    "$TMP/n/число.lisp" "$target" >"$TMP/n/encode.log"
  test "$(wc -c < "$target")" -eq 5
}
native=0; oracle=0
while read -r a b sum sub; do
  encode "$a" "$TMP/n/a.sens"
  encode "$b" "$TMP/n/b.sens"
  cat "$TMP/n/a.sens" "$TMP/n/b.sens" >"$TMP/n/args.sens"
  test "$(wc -c < "$TMP/n/args.sens")" -eq 10
  for op in add7 sub7; do
    if [[ "$op" = add7 ]]; then wanted="$sum";head='додати'
    else wanted="$sub";head='відняти'; fi
    encode "$wanted" "$TMP/n/expected.sens"
    timeout 12s "$TMP/$op.direct.elf" <"$TMP/n/args.sens" \
      >"$TMP/n/result.sens" 2>"$TMP/n/native.err"
    test ! -s "$TMP/n/native.err"
    cmp "$TMP/n/expected.sens" "$TMP/n/result.sens"
    native=$((native+1))
    if [[ "$MODE" = full ]]; then
      printf '(%s %s %s)\n' "$head" "$a" "$b" >"$TMP/n/форма.lisp"
      timeout 90s "$ORACLE" "$TMP/n/форма.lisp" \
        >"$TMP/n/oracle.out" 2>"$TMP/n/oracle.err"
      test ! -s "$TMP/n/oracle.err"
      printf '%s\n' "$wanted" >"$TMP/n/wanted"
      cmp "$TMP/n/wanted" "$TMP/n/oracle.out"
      oracle=$((oracle+1))
    fi
  done
done < "$TMP/vectors"
test "$native" -eq 16
if [[ "$MODE" = full ]]; then
  test "$oracle" -eq 16; verdict=16
else
  test "$oracle" -eq 0; verdict=NOT-CHECKED
fi
# Той самий ELF мусить відхилити нецілі фізичні runtime кадри.
encode 7 "$TMP/n/a.sens"
encode -3 "$TMP/n/b.sens"
cat "$TMP/n/a.sens" "$TMP/n/b.sens" >"$TMP/n/valid.sens"
: >"$TMP/n/empty.sens"
head -c 9 "$TMP/n/valid.sens" >"$TMP/n/short.sens"
cp "$TMP/n/valid.sens" "$TMP/n/extra.sens"
printf '\000' >>"$TMP/n/extra.sens"
cp "$TMP/n/valid.sens" "$TMP/n/bad.sens"
python3 - "$TMP/n/bad.sens" <<'PY'
from pathlib import Path
import sys
path=Path(sys.argv[1]);data=bytearray(path.read_bytes())
data[5]=255
path.write_bytes(data)
PY
negative_stdin=0
for name in empty short extra bad;do
  rc=0
  timeout 8s "$TMP/add7.direct.elf" <"$TMP/n/$name.sens" \
    >"$TMP/n/$name.out" 2>"$TMP/n/$name.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/n/$name.out" && test ! -s "$TMP/n/$name.err"
  negative_stdin=$((negative_stdin+1))
done
negative_source=0
reject() {
  local tag="$1";shift
  local dest="$TMP/$tag.elf" rc=0
  timeout 45s "$TMP/bin/sensdvaparampriamoelf" \
    --скомпілювати-два-D24-stdin "$@" "$dest" \
    >"$TMP/$tag.out" 2>"$TMP/$tag.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$dest" && test ! -L "$dest"
  test ! -s "$TMP/$tag.out"
  grep -Fq 'ДВА-D24-ПРЯМО-ВІДМОВА:' "$TMP/$tag.err"
  negative_source=$((negative_source+1))
}
r="$TMP/cases/add7"
reject corrupt "$TMP/cases/bad-corrupt.sens" "$r.p1.sens" "$r.p2.sens"
reject wrong-head "$TMP/cases/bad-body.sens" "$r.p1.sens" "$r.p2.sens"
reject wrong-name "$r.body.sens" "$TMP/cases/bad-name.sens" "$r.p2.sens"
reject duplicate "$r.body.sens" "$r.p1.sens" "$r.p1.sens"
reject missing "$TMP/cases/missing.sens" "$r.p1.sens" "$r.p2.sens"
cp "$r.body.sens" "$TMP/cases/not-canonical.lisp"
reject projection "$TMP/cases/not-canonical.lisp" "$r.p1.sens" "$r.p2.sens"
test "$negative_source" -eq 6
# Опубліковані ELF ніколи не замінюють ціль, включно із symlink.
cp "$TMP/add7.direct.elf" "$TMP/occupied.elf"
rc=0
timeout 45s "$TMP/bin/sensdvaparampriamoelf" \
  --скомпілювати-два-D24-stdin "$r.body.sens" "$r.p1.sens" \
  "$r.p2.sens" "$TMP/occupied.elf" >"$TMP/no-clobber.out" \
  2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/no-clobber.out"
cmp "$TMP/add7.direct.elf" "$TMP/occupied.elf"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 45s "$TMP/bin/sensdvaparampriamoelf" \
  --скомпілювати-два-D24-stdin "$r.body.sens" "$r.p1.sens" \
  "$r.p2.sens" "$TMP/dangling.elf" >"$TMP/symlink.out" \
  2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/nonexistent.elf"
test ! -s "$TMP/symlink.out"
echo "G6.182-ПРЯМО-D24-ELF-ГАРАЗД fpc=checked source=2 byte-identical=2 native=$native oracle=$verdict bad-stdin=$negative_stdin bad-source=$negative_source no-clobber=2 energy=NOT-MEASURED"
