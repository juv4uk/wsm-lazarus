#!/usr/bin/env bash
# G6.242 — один host publisher для вже доведених фізичних D3 ELF.
# Немає нового SENS закону, текстового D7-dispatch чи Rust/Zig build.
# 1) Чому umask=000 не повинен розширити права власного ELF0700?
# 2) Чому fchmod(fd), а не chmod(path), прибирає одну path-race?
# 3) Чому no-clobber має відхилити також dangling symlink?
# 4) Чому реальний запуск x86-64 необхідний крім cmp(ELF)?
# 5) Чому успіх після негативу перевіряє цілісність виклику?
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D3-ПУБЛІКАЦІЯ-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in git fpc timeout cmp readelf mktemp grep stat sed find; do
  command -v "$tool" >/dev/null || {
    echo "D3-ПУБЛІКАЦІЯ-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 50 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/eq" "$TMP/nested" "$TMP/published"
build() {
  local source="$1" binary="$2"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/build-$binary.log" 2>&1 || {
    cat "$TMP/build-$binary.log" >&2; exit 1;
  }
}
build src/sensd3kompiliator.lpr sensd3kompiliator
build scripts/test-ircallwriter.pas test-ircallwriter
build scripts/test-irnestedeqcall.pas test-irnestedeqcall

HEAPTRC="log=$TMP/heap-eq.log" timeout 60s \
  "$TMP/bin/test-ircallwriter" "$TMP/eq" >"$TMP/eq.log" 2>"$TMP/eq.err"
HEAPTRC="log=$TMP/heap-nested.log" timeout 60s \
  "$TMP/bin/test-irnestedeqcall" "$TMP/nested" >"$TMP/nested.log" \
  2>"$TMP/nested.err"
grep -Fq 'G6_107_OK ELF=4 PHYS_NEG=13 HOST_NEG=12' "$TMP/eq.log"
grep -Fq 'G6_119_OK ELF=16 NEG=18 CALLS=3 RET=1' "$TMP/nested.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap-eq.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap-nested.log"

umask 000
GOOD=0
EQ=0
NESTED=0
for group in eq nested; do
  for source in "$TMP/$group"/*.sens; do
    case "$source" in *.expected.sens) continue ;; esac
    stem=$(printf '%s\n' "$source" | sed 's/\.sens$//')
    name=$(basename "$stem")
    expected="$stem.expected.sens"
    donor="$stem.elf"
    output="$TMP/published/$group-$name.elf"
    [[ -s "$source" && -s "$expected" && -s "$donor" ]]
    timeout 10s "$TMP/bin/sensd3kompiliator" --породити "$source" \
      "$output" >"$TMP/cli.log" 2>"$TMP/cli.err"
    test ! -s "$TMP/cli.err"
    grep -Fq 'ELF64-байтів=' "$TMP/cli.log"
    [[ -x "$output" ]]
    [[ $(stat -c '%a' "$output") == 700 ]]
    timeout 5s readelf -h "$output" >"$TMP/header.log"
    grep -Eq 'Type:.*DYN' "$TMP/header.log"
    cmp "$output" "$donor"
    timeout 5s "$output" >"$TMP/actual.sens" 2>"$TMP/native.err"
    test ! -s "$TMP/native.err"
    cmp "$TMP/actual.sens" "$expected"
    [[ $(wc -c <"$TMP/actual.sens") -eq 1 ]]
    GOOD=$((GOOD+1))
    if [[ "$group" == eq ]]; then EQ=$((EQ+1))
    else NESTED=$((NESTED+1)); fi
  done
done
[[ "$GOOD" -eq 20 && "$EQ" -eq 4 && "$NESTED" -eq 16 ]]

VALID="$TMP/eq/рівність-11.sens"
[[ -s "$VALID" ]]
REJECTED=0
reject() {
  local code="$1"
  shift
  local actual=0
  timeout 10s "$TMP/bin/sensd3kompiliator" "$@" \
    >"$TMP/rejected.log" 2>"$TMP/rejected.err" || actual=$?
  if [[ "$actual" -ne "$code" ]] || [[ -s "$TMP/rejected.log" ]] \
     || [[ ! -s "$TMP/rejected.err" ]]; then
    echo "D3-ПУБЛІКАЦІЯ-ВІДМОВА: expected=$code actual=$actual" >&2
    exit 1
  fi
  REJECTED=$((REJECTED+1))
}
printf 'НЕ-ПЕРЕЗАПИСУВАТИ' >"$TMP/published/existing.elf"
reject 2 --породити "$VALID" "$TMP/published/existing.elf"
[[ $(cat "$TMP/published/existing.elf") == 'НЕ-ПЕРЕЗАПИСУВАТИ' ]]
ln -s "$TMP/published/existing.elf" "$TMP/published/linked.elf"
reject 2 --породити "$VALID" "$TMP/published/linked.elf"
[[ -L "$TMP/published/linked.elf" ]]
[[ $(cat "$TMP/published/existing.elf") == 'НЕ-ПЕРЕЗАПИСУВАТИ' ]]
ln -s "$TMP/no-such-elf" "$TMP/published/dangling.elf"
reject 2 --породити "$VALID" "$TMP/published/dangling.elf"
[[ -L "$TMP/published/dangling.elf" && ! -e "$TMP/no-such-elf" ]]
reject 2 --породити "$VALID" "$TMP/absent-directory/failed.elf"
[[ ! -e "$TMP/absent-directory/failed.elf" ]]
reject 2 --породити "$TMP/no-input.sens" "$TMP/published/no-input.elf"
[[ ! -e "$TMP/published/no-input.elf" ]]
: >"$TMP/empty.sens"
reject 2 --породити "$TMP/empty.sens" "$TMP/published/empty.elf"
[[ ! -e "$TMP/published/empty.elf" ]]
printf '\363' >"$TMP/broken.sens"
reject 2 --породити "$TMP/broken.sens" "$TMP/published/broken.elf"
[[ ! -e "$TMP/published/broken.elf" ]]
printf '(тотожне? так так)\n' >"$TMP/text.sens"
reject 2 --породити "$TMP/text.sens" "$TMP/published/text.elf"
[[ ! -e "$TMP/published/text.elf" ]]
reject 64 --породити "$TMP/text.lisp" "$TMP/published/wrong.elf"
[[ ! -e "$TMP/published/wrong.elf" ]]

# Старі d3cXXXXXX і спільні senXXXXXX не можуть залишатися в каталозі.
if find "$TMP/published" -maxdepth 1 -type f \
  \( -name 'sen??????' -o -name 'd3c??????' \) | grep -q .; then
  echo 'D3-ПУБЛІКАЦІЯ-ПОМИЛКА: залишено тимчасовий inode' >&2
  exit 1
fi

# Публікація та машинне виконання після всіх негативів: відновлення.
timeout 10s "$TMP/bin/sensd3kompiliator" --породити "$VALID" \
  "$TMP/published/recovery.elf" >"$TMP/cli.log" 2>"$TMP/cli.err"
test ! -s "$TMP/cli.err"
[[ $(stat -c '%a' "$TMP/published/recovery.elf") == 700 ]]
cmp "$TMP/published/recovery.elf" "$TMP/eq/рівність-11.elf"
timeout 5s "$TMP/published/recovery.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/eq/рівність-11.expected.sens"
[[ "$REJECTED" -eq 9 ]]
echo "VERIFIED-D3-PUBLISH-PASS fpc=checked physical=$GOOD simple=$EQ nested=$NESTED native=$GOOD reject=$REJECTED recovery=1 no-clobber=так mode=0700 heap=zero oracle=SEPARATE energy=NOT-MEASURED"
