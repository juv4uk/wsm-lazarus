#!/usr/bin/env bash
# G6.151 — реальна відтворюваність двох незалежних FPC збірок
# фізичних pinned Core1/D24 тіл. Тільки механічний host gate.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for tool in fpc git timeout cmp diff readelf grep mktemp cp tail wc; do
  command -v "$tool" >/dev/null || { echo "НЕМАЄ-ІНСТРУМЕНТА: $tool" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
ORACLE="$(printenv SENS_ORACLE_BIN 2>/dev/null || true)"
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'НЕМАЄ-НЕЗАЛЕЖНОГО-SENS-ОРАКУЛА' >&2; exit 127;
}
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc)); then
    echo "ВІДТВОРЮВАНІСТЬ-ELF-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 18 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP"/{generator,original,relocated,immutable}
# T5M fixtures узяті з наявного pinned генератора, не з нового
# опису мовних законів у Bash. Manifest містить лише host-параметри.
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/generator" -FE"$TMP/generator" \
  -otest-bodyfile-compiler "$ROOT/scripts/test-bodyfile-compiler.pas" \
  >"$TMP/generator.build" 2>&1 || { cat "$TMP/generator.build" >&2; exit 1; }
HEAPTRC="log=$TMP/generator.heap" timeout 90s \
  "$TMP/generator/test-bodyfile-compiler" "$ROOT" "$TMP/original" \
  >"$TMP/manifest.tsv" 2>"$TMP/generator.err"
test "$(wc -l <"$TMP/manifest.tsv")" -eq 9
grep -Fq 'BODY-FILE-FIXTURES-OK cases=9 negatives=5' "$TMP/generator.err"
grep -Fq '0 unfreed memory blocks' "$TMP/generator.heap"
cp -a "$TMP/original/." "$TMP/relocated/"
cp -a "$TMP/original/." "$TMP/immutable/"
# Незалежно перекомпілюємо компілятор в різні FPC каталоги.
for stage in original relocated; do
  mkdir -p "$TMP/$stage/units" "$TMP/$stage/bin" "$TMP/$stage/out"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$stage/units" -FE"$TMP/$stage/bin" \
    -osensbodyfileelf "$ROOT/src/sensbodyfileelf.lpr" \
    >"$TMP/$stage.build" 2>&1 || { cat "$TMP/$stage.build" >&2; exit 1; }
  test -x "$TMP/$stage/bin/sensbodyfileelf"
done
# $mode/$tag/$wanted — лише manifest уже виконуваного fixture.
# Точні D7 і D24 залишаються незмінними фізичними файлами .sens.
build_args() {
  local prefix="$1" mode="$2"
  ARGS=()
  case "$mode" in
    1) ARGS=(--один-D24 "$prefix.body.sens" "$prefix.p1.sens" "$prefix.a1.sens");;
    A|S) ARGS=(--два-D24 "$prefix.body.sens" "$prefix.p1.sens" \
        "$prefix.p2.sens" "$prefix.a1.sens" "$prefix.a2.sens");;
    R) ARGS=(--два-D24-самовиклик "$prefix.body.sens" "$prefix.p1.sens" \
        "$prefix.p2.sens" "$prefix.self.sens" "$prefix.a1.sens" "$prefix.a2.sens");;
    *) echo "НЕВІДОМИЙ-МЕХАНІЧНИЙ-РЕЖИМ: $mode" >&2; exit 2;;
  esac
}
case_count=0
while IFS=$'\t' read -r tag mode a b wanted op; do
  [[ -n "$tag" ]] || continue
  for stage in original relocated; do
    prefix="$TMP/$stage/$tag"
    build_args "$prefix" "$mode"
    target="$TMP/$stage/out/$tag.elf"
    HEAPTRC="log=$TMP/$stage-$tag.heap" timeout 40s \
      "$TMP/$stage/bin/sensbodyfileelf" "${ARGS[@]}" "$target" \
      >"$TMP/$stage-$tag.out" 2>"$TMP/$stage-$tag.err"
    grep -Fq 'SENS-BODY-AOT-ELF64' "$TMP/$stage-$tag.out"
    test ! -s "$TMP/$stage-$tag.err"
    grep -Fq '0 unfreed memory blocks' "$TMP/$stage-$tag.heap"
    test -x "$target"
    readelf -h "$target" | grep -Eq 'Type:[[:space:]]+EXEC'
    if readelf -l "$target" | grep -Eq 'INTERP|DYNAMIC'; then
      echo 'ДИНАМІЧНИЙ-ЗАВАНТАЖУВАЧ-НЕ-ПРИПУСТИМИЙ' >&2; exit 1
    fi
    actual=0
    timeout 8s "$target" >"$TMP/$stage-$tag.stdout" \
      2>"$TMP/$stage-$tag.machine.err" || actual=$?
    test ! -s "$TMP/$stage-$tag.stdout"
    test ! -s "$TMP/$stage-$tag.machine.err"
    expected=$(((wanted % 256 + 256) % 256))
    if ((actual != expected)); then
      echo "НЕЗБІГ-ВИКОНАННЯ-$tag: очікували=$expected, отримали=$actual" >&2
      exit 1
    fi
  done
  cmp "$TMP/original/out/$tag.elf" "$TMP/relocated/out/$tag.elf"
  case_count=$((case_count+1))
done <"$TMP/manifest.tsv"
test "$case_count" -eq 9
# На вході незмінні фізичні .sens, без випадкового перезапису.
diff -qr "$TMP/original" "$TMP/immutable" \
  --exclude=bin --exclude=units --exclude=out >/dev/null
diff -qr "$TMP/relocated" "$TMP/immutable" \
  --exclude=bin --exclude=units --exclude=out >/dev/null
IFS=$'\t' read -r first_tag first_mode _ <"$TMP/manifest.tsv"
cp "$TMP/original/out/$first_tag.elf" "$TMP/occupied.elf"
build_args "$TMP/original/$first_tag" "$first_mode"
rc=0
HEAPTRC="log=$TMP/occupied.heap" timeout 40s \
  "$TMP/original/bin/sensbodyfileelf" "${ARGS[@]}" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/original/out/$first_tag.elf"
# Незалежний pinned SENS CLI у чинному регресійному gate.
timeout 600s bash scripts/test-bodyfile-compiler.sh
printf 'ВІДТВОРЮВАНІСТЬ-AOT-ELF64-ГАРАЗД: checked-builds=2 physical-cases=%d executable=18 byte-identical=%d no-clobber=1 original-oracle=yes energy=NOT_MEASURED\n' \
  "$case_count" "$case_count"
# Питання: 1) Чому однаковий exit-low8 не доводить однаковий ELF?
# 2) Чому людський D7 напис не може визначати виклик мовного закону?
# 3) Чому source .sens не повинен змінюватися під час AOT?
# 4) Чому ця матриця не доводить компіляцію всього Core1?
