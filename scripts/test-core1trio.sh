#!/usr/bin/env bash
# G6.150 — три оригінальні фізичні Core1 DEFINE в одному AOT-запуску.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЯДРО1-ТРІО-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in timeout git fpc cmp mktemp readelf sha256sum grep; do
  command -v "$t" >/dev/null || {
    echo "ЯДРО1-ТРІО-БЛОК: немає $t" >&2;exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test -s external/sens/lib/core1.sens
for name in ядро1-додати ядро1-відняти ядро1-помножити;do
  grep -Fq "(визначити $name" external/sens/lib/core1.lisp
done
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc != 0));then
    echo "ЯДРО1-ТРІО-ПОМИЛКА rc=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err;do
      [[ ! -s "$f" ]] || { echo "---- $f" >&2;tail -n 55 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for spec in 'src/senscore1trioelf.lpr:senscore1trioelf' \
            'scripts/test-core1trio-fixtures.pas:test-core1trio-fixtures';do
  IFS=: read -r source exe <<<"$spec"
  timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/fixture.heap" timeout 90s \
  "$TMP/bin/test-core1trio-fixtures" "$ROOT" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2;exit 1;
  }
grep -Fq 'пар=4 pinned-викликів=12' "$TMP/fixtures.log"
test -s "$TMP/fixture.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
test ! -s "$TMP/fixtures.err"
pass=0;wide=0;oracle=0
while IFS=$'\t' read -r label a b expect_add expect_sub expect_mul;do
  test -n "$label"
  result="$TMP/$label"
  HEAPTRC="log=$TMP/$label.heap" timeout 90s \
    "$TMP/bin/senscore1trioelf" --скомпілювати-три-ядро1 \
    "$TMP/physical/$label.left.sens" "$TMP/physical/$label.right.sens" \
    "$result" >"$TMP/$label.compile.log" 2>"$TMP/$label.err" || {
      cat "$TMP/$label.err" >&2;exit 1;
    }
  grep -Fq 'ЯДРО1-ТРІО-ГОТОВО:' "$TMP/$label.compile.log"
  test -s "$TMP/$label.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  test ! -s "$TMP/$label.err"
  test "$(stat -c %a "$result")" -eq 700
  for op in add sub mul;do
    case "$op" in
      add) filename=додати;projection=додати;expected="$expect_add" ;;
      sub) filename=відняти;projection=відняти;expected="$expect_sub" ;;
      mul) filename=помножити;projection=помножити;expected="$expect_mul" ;;
      *) exit 99 ;;
    esac
    elf="$result/$filename.elf"
    test -x "$elf"
    timeout 5s readelf -h "$elf" >"$TMP/$label.$op.elf.log"
    grep -Eq 'Type:.*DYN' "$TMP/$label.$op.elf.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.$op.elf.log"
    timeout 5s "$elf" >"$TMP/$label.$op.out.sens" \
      2>"$TMP/$label.$op.exec.err"
    test ! -s "$TMP/$label.$op.exec.err"
    cmp "$TMP/$label.$op.out.sens" \
      "$TMP/physical/$label.$op.expected.sens"
    if [[ "$(wc -c < "$TMP/$label.$op.out.sens")" -eq 5 ]];then
      wide=$((wide+1))
    fi
    if [[ -n "${SENS_ORACLE_BIN:-}" ]];then
      test -x "$SENS_ORACLE_BIN"
      test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
      printf '(%s %s %s)\n' "$projection" "$a" "$b" \
        >"$TMP/$label.$op.oracle.lisp"
      timeout 90s "$SENS_ORACLE_BIN" "$TMP/$label.$op.oracle.lisp" \
        >"$TMP/$label.$op.oracle.out" 2>"$TMP/$label.$op.oracle.err"
      test ! -s "$TMP/$label.$op.oracle.err"
      printf '%s\n' "$expected" >"$TMP/$label.$op.expect.txt"
      cmp "$TMP/$label.$op.oracle.out" "$TMP/$label.$op.expect.txt"
      oracle=$((oracle+1))
    fi
    pass=$((pass+1))
  done
done <"$TMP/physical/cases.tsv"
test "$pass" -eq 12
test "$wide" -ge 1
if [[ -n "${SENS_ORACLE_BIN:-}" ]];then test "$oracle" -eq 12;fi

# Повторний AOT не має ніяких недетермінованих машинних байтів.
HEAPTRC="log=$TMP/repeat.heap" timeout 60s \
 "$TMP/bin/senscore1trioelf" --скомпілювати-три-ядро1 \
 "$TMP/physical/01.left.sens" "$TMP/physical/01.right.sens" \
 "$TMP/repeat" >"$TMP/repeat.log" 2>"$TMP/repeat.err"
for filename in додати відняти помножити;do
  cmp "$TMP/01/$filename.elf" "$TMP/repeat/$filename.elf"
done

reject() {
  local name="$1";shift
  local output="$TMP/reject-$name" rc=0
  HEAPTRC="log=$TMP/reject-$name.heap" timeout 35s \
    "$TMP/bin/senscore1trioelf" --скомпілювати-три-ядро1 \
    "$@" "$output" >"$TMP/reject-$name.log" \
    2>"$TMP/reject-$name.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/reject-$name.log"
  grep -Fq 'ЯДРО1-ТРІО-ВІДМОВА:' "$TMP/reject-$name.err"
}
cp "$TMP/physical/01.left.sens" "$TMP/physical/projection.lisp"
: > "$TMP/physical/empty.sens"
reject projection "$TMP/physical/projection.lisp" "$TMP/physical/01.right.sens"
reject corrupt "$TMP/physical/corrupt.sens" "$TMP/physical/01.right.sens"
reject wrong-width "$TMP/physical/wrong-width.sens" "$TMP/physical/01.right.sens"
reject empty "$TMP/physical/empty.sens" "$TMP/physical/01.right.sens"
reject missing "$TMP/physical/absent.sens" "$TMP/physical/01.right.sens"
# Випробуємо атомарний mkdir/no-clobber: раніше створений output dir
# не повинен бути змінений, зокрема якщо містить symbolic link.
cp -a "$TMP/01" "$TMP/occupied"
before="$(sha256sum "$TMP/occupied/додати.elf" | cut -d' ' -f1)"
rc=0
HEAPTRC="log=$TMP/occupied.heap" timeout 60s \
 "$TMP/bin/senscore1trioelf" --скомпілювати-три-ядро1 \
 "$TMP/physical/01.left.sens" "$TMP/physical/01.right.sens" \
 "$TMP/occupied" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && ! test -s "$TMP/occupied.out"
grep -Fq 'ВІДМОВА:' "$TMP/occupied.err"
test "$(sha256sum "$TMP/occupied/додати.elf" | cut -d' ' -f1)" = "$before"

# Помилкові параметри й output parent також fail-closed.
rc=0
"$TMP/bin/senscore1trioelf" --невірний-режим \
 "$TMP/physical/01.left.sens" "$TMP/physical/01.right.sens" \
 "$TMP/wrong-mode" >"$TMP/wrong-mode.out" 2>"$TMP/wrong-mode.err" || rc=$?
test "$rc" -eq 2 && ! test -e "$TMP/wrong-mode"
rc=0
"$TMP/bin/senscore1trioelf" --скомпілювати-три-ядро1 \
 "$TMP/physical/01.left.sens" "$TMP/physical/01.right.sens" \
 "$TMP/nonexistent/nested" >"$TMP/wrong-parent.out" \
 2>"$TMP/wrong-parent.err" || rc=$?
test "$rc" -eq 2 && ! test -e "$TMP/nonexistent"
timeout 120s bash scripts/check-no-lcl.sh >"$TMP/no-lcl.log"
echo "ЯДРО1-ТРІО-ВЕРИФІКОВАНО native=$pass D24=$wide oracle=$oracle negatives=8 reproducible=3 pinned=так memory=0 energy=NOT-MEASURED"
