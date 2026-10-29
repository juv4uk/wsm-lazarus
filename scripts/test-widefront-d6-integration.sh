#!/usr/bin/env bash
# G6.136 — інтеграція вже ратифікованих фізичних D6 НСД/остача:
# спільний WideIR -> ті самі машинні ELF, що спеціалізовані front-end.
# Це механічний тест, а не нове тлумачення законів або Core1 у Pascal.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д6-ІНТЕГРАЦІЯ-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for cmd in fpc git timeout cmp readelf objdump grep mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "Д6-ІНТЕГРАЦІЯ-БЛОК: відсутня команда $cmd" >&2;exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010101 (ук нсд) (укр найбільший-спільний-дільник)' \
  external/sens/lib/domains/d6.lisp
grep -Fq '(010100 (ук остача) (укр остача)' \
  external/sens/lib/domains/d6.lisp
ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ "$(printenv REQUIRE_SENS_ORACLE || echo 0)" == 1 && -z "$ORACLE" ]]; then
  echo 'Д6-ІНТЕГРАЦІЯ-БЛОК: обов’язковий незалежний pinned SENS' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi

TMP=$(mktemp -d)
finish() {
  local status="$1" line="$2" f
  if (( status != 0 )); then
    echo "Д6-ІНТЕГРАЦІЯ-RED: код=$status рядок=$line" >&2
    for f in "$TMP"/*.build "$TMP"/*.err \
             "$TMP"/нсд/fixtures.out "$TMP"/остача/fixtures.out \
             "$TMP"/нсд/*.compile.err "$TMP"/остача/*.compile.err \
             "$TMP"/нсд/*.oracle.err "$TMP"/остача/*.oracle.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 12 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$status"
}
trap 'finish "$?" "$LINENO"' EXIT
trap 'echo "Д6-ІНТЕГРАЦІЯ-КОМАНДА: рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/нсд" "$TMP/остача"
FPC_BIN=$(printenv FPC || echo fpc)
for pair in \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidensdelf.lpr senswidensdelf' \
  'src/senswiderestelf.lpr senswiderestelf' \
  'scripts/test-irwidensd.pas test-irwidensd' \
  'scripts/test-irwiderest.pas test-irwiderest'; do
  read -r source binary <<<"$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>&1 || {
      cat "$TMP/$binary.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$binary"
done

# Генератори: borrowed pinned фізичні D6/D12, унікальні приватні теки;
# результат — власні файли T5M і TSV. Пам'ять FPC очищується після процесу.
# 1) Чому TSV не дає семантики?
# 2) Як збережено W12 і D2 framing?
# 3) Хто володіє generated фізичними файлами?
for fixture in 'нсд test-irwidensd 14' 'остача test-irwiderest 28'; do
  read -r kind generator amount <<<"$fixture"
  timeout 30s "$TMP/bin/$generator" "$TMP/$kind" \
    >"$TMP/$kind/fixtures.out" 2>"$TMP/$kind/fixtures.err"
  if [[ "$kind" == нсд ]]; then
    grep -Fq "G6.105-NSD-FIXTURES-OK cases=$amount" \
      "$TMP/$kind/fixtures.out"
  else
    grep -Fq "G6.102-REST-FIXTURES-OK cases=$amount" \
      "$TMP/$kind/fixtures.out"
  fi
  if grep -Fq 'unfreed memory blocks' "$TMP/$kind/fixtures.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/$kind/fixtures.err"
  fi
done

MODE=--скомпілювати-фізичну-форму
MACHINE=0;REPEAT=0;ORACLE_COUNT=0;NSD=0;REST=0
for kind in нсд остача; do
  dir="$TMP/$kind"
  while IFS=$'\t' read -r tag left right wanted; do
    test -n "$tag"
    full="$dir/$tag.sens"
    elf="$dir/$tag.elf"
    old="$dir/$tag.special.elf"
    timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" "$full" "$elf" \
      >"$dir/$tag.compile.out" 2>"$dir/$tag.compile.err"
    test -x "$elf"
    grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$dir/$tag.compile.out"
    readelf -h "$elf" >"$dir/$tag.header"
    grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$dir/$tag.header"
    grep -Fq 'Advanced Micro Devices X86-64' "$dir/$tag.header"
    readelf -l "$elf" >"$dir/$tag.segments"
    ! grep -Eq 'INTERP|DYNAMIC' "$dir/$tag.segments"
    tail -c +121 "$elf" >"$dir/$tag.machine"
    objdump -D -b binary -m i386:x86-64 -M intel \
      "$dir/$tag.machine" >"$dir/$tag.disassembly"
    if [[ "$kind" == нсд ]]; then
      grep -Eiq 'div[[:space:]]+ecx' "$dir/$tag.disassembly"
      grep -Eiq 'test[[:space:]]+ecx,ecx' "$dir/$tag.disassembly"
      timeout 25s "$TMP/bin/senswidensdelf" --скомпілювати-D6-нсд-D12 \
        "$full" "$old" >"$dir/$tag.special.out" 2>"$dir/$tag.special.err"
      surface=найбільший-спільний-дільник
      NSD=$((NSD+1))
    else
      grep -Eiq 'idiv[[:space:]]+rcx' "$dir/$tag.disassembly"
      grep -Eiq 'cqo' "$dir/$tag.disassembly"
      timeout 25s "$TMP/bin/senswiderestelf" --скомпілювати-D6-остача-D12 \
        "$full" "$old" >"$dir/$tag.special.out" 2>"$dir/$tag.special.err"
      surface=остача
      REST=$((REST+1))
    fi
    # Обидва незалежні front-end мають дати ОДНАКОВИЙ машинний файл,
    # не лише однакове обчислене значення.
    cmp "$elf" "$old"
    timeout 5s "$elf" >"$dir/$tag.actual.sens" 2>"$dir/$tag.execute.err"
    test ! -s "$dir/$tag.execute.err"
    cmp "$dir/$tag.actual.sens" "$dir/$tag.expected.sens"
    test "$(wc -c <"$dir/$tag.actual.sens")" -eq 3
    timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
      "$full" "$dir/$tag.repeat.elf" \
      >"$dir/$tag.repeat.out" 2>"$dir/$tag.repeat.err"
    cmp "$elf" "$dir/$tag.repeat.elf"
    REPEAT=$((REPEAT+1))
    if [[ -n "$ORACLE" ]]; then
      printf '(%s %s %s)\n' "$surface" "$left" "$right" >"$dir/$tag.lisp"
      timeout 60s "$ORACLE" "$dir/$tag.lisp" \
        >"$dir/$tag.oracle.out" 2>"$dir/$tag.oracle.err"
      test ! -s "$dir/$tag.oracle.err"
      printf '%s\n' "$wanted" >"$dir/$tag.wanted"
      cmp "$dir/$tag.wanted" "$dir/$tag.oracle.out"
      ORACLE_COUNT=$((ORACLE_COUNT+1))
    fi
    MACHINE=$((MACHINE+1))
  done <"$dir/cases.tsv"
done
test "$MACHINE" -eq 42
test "$NSD" -eq 14 && test "$REST" -eq 28
test "$REPEAT" -eq 42
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 42;fi

# Fail closed: відмова без публікації навіть часткового ELF.
NEG=0
reject() {
  local label="$1" source="$2" target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" "$source" "$target" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
for name in d1 d3-empty d7 d24 missing extra nested two-roots dotted \
            root-atom unclosed close-only bad-t5m empty \
            zero-left zero-right negative-left negative-right; do
  reject "нсд:$name" "$TMP/нсд/$name.sens"
done
for name in d1 d3-empty d7 d24 missing extra nested two-roots dotted \
            root-atom unclosed close-only bad-t5m empty div-zero \
            d24-right d48-left min-left min-right min-both \
            positive-negdiv-width; do
  reject "остача:$name" "$TMP/остача/$name.sens"
done
for kind in нсд остача; do
  reject "$kind:проєкція" "$TMP/$kind/fake.lisp"
  reject "$kind:відсутній" "$TMP/$kind/відсутній.sens"
done
test "$NEG" -eq 43

# Позитивні машини вже перевірені. Публікація no-clobber/відновлення
# не має перетворити негативну спробу на втрату наявної цілі.
NOCLOBBER=0
for kind in нсд остача; do
  src="$TMP/$kind/01.sens"
  cp "$TMP/$kind/01.elf" "$TMP/$kind/occupied.elf"
  rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$src" "$TMP/$kind/occupied.elf" \
    >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
  cmp "$TMP/$kind/occupied.elf" "$TMP/$kind/01.elf"
  NOCLOBBER=$((NOCLOBBER+1))
  ln -s "$TMP/$kind/відсутній.elf" "$TMP/$kind/dangling.elf"
  rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$src" "$TMP/$kind/dangling.elf" \
    >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
  test -L "$TMP/$kind/dangling.elf"
  test ! -e "$TMP/$kind/відсутній.elf"
  NOCLOBBER=$((NOCLOBBER+1))
  timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$src" "$TMP/$kind/recovered.elf" >"$TMP/recovered.out"
  timeout 5s "$TMP/$kind/recovered.elf" >"$TMP/$kind/recovered.sens"
  cmp "$TMP/$kind/recovered.sens" "$TMP/$kind/01.expected.sens"
done
test "$NOCLOBBER" -eq 4
echo "Д6-СПІЛЬНИЙ-ELF-ПРОЙДЕНО НСД=$NSD остача=$REST machine=$MACHINE byte-identical=$MACHINE повтори=$REPEAT oracle=$ORACLE_COUNT негативи=$NEG no-clobber=$NOCLOBBER енергія=НЕ-ВИМІРЯНО"

# Типи: kind/tag — індекси тесту (не dispatch SENS).
# Фізичні інтервали та домен перевіряє чинний pinned WideIR,
# результат ELF-owned публікується через перевірений publisher.
# Тимчасові .ppu/.o, ELF і T5M знищує EXIT trap.
# 1) Чому однакові результати не означають однакові ELF?
# 2) Чому pinned незалежний REPL читає український .lisp?
# 3) Чому нульовий дільник не породжує новий ELF?
# 4) Що доводить no-clobber і чого не доводить?
