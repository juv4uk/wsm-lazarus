#!/usr/bin/env bash
# G6.141 — 36 САМОСТІЙНИХ right-nested SENS D5 програм → ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'echo "Д5-ПРАВИЙ-ТЕСТ-ВІДМОВА рядок=$LINENO код=$?" >&2; for f in "$TMP"/compile.err "$TMP"/oracle.err; do if [[ -f "$f" ]]; then tail -n 10 "$f" >&2; fi; done' ERR
trap 'rm -rf "$TMP"' EXIT
for t in git fpc timeout readelf objdump cmp grep dd;do command -v "$t" >/dev/null;done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 60s ./scripts/check-pin.sh
timeout 60s ./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
mkdir -p "$TMP"/{units,bin,fixture}
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-irarithpravy.pas test-irarithpravy' \
  'src/sensarithpravyelf.lpr sensarithpravyelf' \
  'src/senschyslo.lpr senschyslo'; do
  read -r source binary <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/compile.out" 2>"$TMP/compile.err" || {
      cat "$TMP/compile.out" "$TMP/compile.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 120s "$TMP/bin/test-irarithpravy" "$TMP/fixture" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err" || {
    cat "$TMP/fixture.log" "$TMP/fixture.err" >&2; exit 1;
  }
grep -Fxq 'G6.141-RIGHT-D5-UNIT-OK positive=36 negative=16' "$TMP/fixture.log" || {
  echo 'невідповідний підсумок генератора:' >&2
  cat "$TMP/fixture.log" "$TMP/fixture.err" >&2
  exit 1
}

PASS=0
ORACLES=0
for depth in $(seq 1 8) 16; do
  for k in 0 1 2 3; do
    tag="$depth-$k"
    input="$TMP/fixture/$tag.sens"
    native="$TMP/fixture/$tag.elf"
    test -x "$native" || chmod 500 "$native"
    readelf -h "$native" >"$TMP/header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
    if readelf -l "$native" | grep -Eq 'INTERP|DYNAMIC'; then
      echo 'ELF має динамічну залежність' >&2; exit 1
    fi
    timeout 5s "$native" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.err"
    test ! -s "$TMP/$tag.err"
    cmp "$TMP/fixture/$tag.expected.sens" "$TMP/$tag.actual.sens"
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
    timeout 15s "$TMP/bin/sensarithpravyelf" --правий-ланцюг-D5 \
      "$input" "$TMP/$tag.cli.elf" >"$TMP/$tag.cli.out" 2>"$TMP/$tag.cli.err"
    cmp "$native" "$TMP/$tag.cli.elf"
    grep -Fq 'Д5-ПРАВИЙ-ЛАНЦЮГ-ГОТОВО:' "$TMP/$tag.cli.out"

    # Машина виконує ВСІ операції, не тільки precomputed literal.
    neg=$((depth / 2))
    length=$((5 + 5 * depth + 2 * neg))
    dd if="$native" of="$TMP/$tag.code" bs=1 skip=120 count="$length" status=none
    objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$tag.code" >"$TMP/$tag.dis"
    count_add=$(grep -Ec '[[:space:]]add[[:space:]]+eax,' "$TMP/$tag.dis" || true)
    count_neg=$(grep -Ec '[[:space:]]neg[[:space:]]+eax' "$TMP/$tag.dis" || true)
    test "$count_add" -eq "$depth"
    test "$count_neg" -eq "$neg"

    if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
      test -x "$SENS_ORACLE_BIN"
      test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
      case "$k" in 0) base=-1900;; 1) base=-7;; 2) base=0;; 3) base=1200;; esac
      nested="$base"
      lefts=(3 -7 11 -2)
      for ((i=depth-1;i>=0;i--));do
        left="${lefts[i%4]}"
        if ((i % 2 == 0)); then
          nested="(додати $left $nested)"
        else
          nested="(відняти $left $nested)"
        fi
      done
      printf '%s\n' "$nested" >"$TMP/oracle.lisp"
      timeout 60s "$SENS_ORACLE_BIN" "$TMP/oracle.lisp" \
        >"$TMP/oracle.out" 2>"$TMP/oracle.err"
      test ! -s "$TMP/oracle.err"
      timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
        "$TMP/$tag.actual.sens" >"$TMP/machine.ukr"
      cmp "$TMP/oracle.out" "$TMP/machine.ukr"
      ORACLES=$((ORACLES+1))
    fi
    PASS=$((PASS+1))
  done
done
test "$PASS" -eq 36

# Новий ELF без перезапису або підміни символьного посилання.
cp "$TMP/fixture/1-1.elf" "$TMP/occupied.elf"
rc=0
timeout 15s "$TMP/bin/sensarithpravyelf" --правий-ланцюг-D5 \
  "$TMP/fixture/1-1.sens" "$TMP/occupied.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
cmp "$TMP/fixture/1-1.elf" "$TMP/occupied.elf"
ln -s "$TMP/notcreated" "$TMP/link.elf"
rc=0
timeout 15s "$TMP/bin/sensarithpravyelf" --правий-ланцюг-D5 \
  "$TMP/fixture/1-1.sens" "$TMP/link.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/link.elf" && test ! -e "$TMP/notcreated"
cp "$TMP/fixture/1-1.sens" "$TMP/projection.lisp"
rc=0
timeout 15s "$TMP/bin/sensarithpravyelf" --правий-ланцюг-D5 \
  "$TMP/projection.lisp" "$TMP/bad.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/bad.elf"
echo "G6.141-ПРАВИЙ-Д5-ГОТОВО physical=$PASS native=$PASS exact-T5M=$PASS negatives=16 oracle=$ORACLES no-clobber=так energy=NOT-MEASURED"
