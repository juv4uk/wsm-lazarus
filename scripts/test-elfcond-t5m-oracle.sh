#!/usr/bin/env bash
# G6.38 — незалежний SENS REPL проти T5M, виконаного справжнім ELF64.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc readelf timeout git cmp awk; do
  command -v "$tool" >/dev/null ||
    { echo "ОРАКУЛ-T5M-БЛОК: потрібен $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
  { echo 'ОРАКУЛ-T5M-БЛОК: потрібен Linux x86-64' >&2; exit 78; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" ||
  { echo 'ОРАКУЛ-T5M-БЛОК: незалежний SENS REPL не зібрано' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" ||
  { echo 'ОРАКУЛ-T5M-БЛОК: неправильний SHA upstream' >&2; exit 1; }
for law in '(yes . D1:1)' '(no . D1:0)' '(identity . D3:000)' \
  '(cond-test . (D1:0 D1:1))' '(cond-after-exhaustion . D3:000)'; do
  grep -Fq "$law" external/sens/contracts/language-contract-12.lisp
done
grep -Fq '(0 (ук ні) (укр ні)' external/sens/lib/domains/d1.lisp
grep -Fq '(1 (ук так) (укр так)' external/sens/lib/domains/d1.lisp
grep -Fq '(000 (ук ()) (укр ())' external/sens/lib/domains/d3.lisp

# Зберігаємо 9 справжніх machine ELF + 9 негативів існуючого FPC gate.
bash ./scripts/test-elfcondt5m.sh
OUT="$ROOT/build/m0.2/elfcond-t5m-oracle"
mkdir -p "$OUT/units" "$OUT/bin"
FPC_BIN=$(printenv FPC || echo fpc)
for item in "src/senst5m.lpr senst5m" "src/sensukrlisp.lpr sensukrlisp"; do
  read -r source target <<< "$item"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$OUT/units" -FE"$OUT/bin" "-o$target" "$ROOT/$source"
done
T5M="$OUT/bin/senst5m"
UKR="$OUT/bin/sensukrlisp"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
# Лише тестова перевірка трьох ратифікованих result-координат.
# Машинний T5M декодує існуючий reader; семантику рахує upstream REPL.
compare_repl() {
  local physical="$1" transcript="$2" bits wanted
  [[ $(stat -c%s "$physical") -eq 1 ]] || return 1
  bits=$("$T5M" --view "$physical") || return 1
  case "$bits" in
    0) wanted='НІ' ;;
    1) wanted='ТАК' ;;
    000) wanted='()' ;;
    *) return 1 ;;
  esac
  awk -v wanted="$wanted" '
    { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
    $0 == wanted || $0 == "sens[укр]> " wanted { hits++ }
    END { exit (hits == 1 ? 0 : 1) }
  ' "$transcript"
}
# Шість негативів test comparator: wrong answer, D12, 2 results,
# malformed transport, empty oracle та .lisp замість фізичного .sens.
printf '1\n' > "$TEMP/one.words"
"$T5M" --pack-words "$TEMP/one.words" > "$TEMP/one.sens"
printf 'sens[укр]> НІ\n' > "$TEMP/wrong.repl"
if compare_repl "$TEMP/one.sens" "$TEMP/wrong.repl"; then
  echo 'ОРАКУЛ-T5M-ПОМИЛКА: хибне НІ прийнято як ТАК' >&2; exit 1
fi
printf '000000000000\n' > "$TEMP/d12.words"
"$T5M" --pack-words "$TEMP/d12.words" > "$TEMP/d12.sens"
printf 'sens[укр]> ТАК\n' > "$TEMP/yes.repl"
if compare_repl "$TEMP/d12.sens" "$TEMP/yes.repl"; then
  echo 'ОРАКУЛ-T5M-ПОМИЛКА: D12 прийнято як D1' >&2; exit 1
fi
printf '0 1\n' > "$TEMP/two.words"
"$T5M" --pack-words "$TEMP/two.words" > "$TEMP/two.sens"
if compare_repl "$TEMP/two.sens" "$TEMP/yes.repl"; then
  echo 'ОРАКУЛ-T5M-ПОМИЛКА: два результати прийнято як один' >&2; exit 1
fi
printf '\363' > "$TEMP/bad.sens"
if compare_repl "$TEMP/bad.sens" "$TEMP/yes.repl" 2>"$TEMP/bad.err"; then
  echo 'ОРАКУЛ-T5M-ПОМИЛКА: зіпсований T5M прийнято' >&2; exit 1
fi
: > "$TEMP/empty.repl"
if compare_repl "$TEMP/one.sens" "$TEMP/empty.repl"; then
  echo 'ОРАКУЛ-T5M-ПОМИЛКА: порожній REPL прийнято' >&2; exit 1
fi
printf '(за-умовою (так ні))\n' > "$TEMP/fake.lisp"
if "$UKR" --вивести-ук "$TEMP/fake.lisp" "$TEMP/fake-project.lisp" \
  >"$TEMP/fake.stdout" 2>"$TEMP/fake.stderr"; then
  echo 'ОРАКУЛ-T5M-ПОМИЛКА: .lisp видано за .sens' >&2; exit 1
fi
test ! -e "$TEMP/fake-project.lisp"
test ! -s "$TEMP/fake.stdout"

W="$ROOT/build/m0.2/elfcondt5m/witnesses"
COUNT=0 NO=0 YES=0 EMPTY=0 EQ=0
for label in вичерпання істинна-одиниця істинний-нуль хибна-умова \
  друга-гілка рівність-істина рівність-хиба рівність-у-тесті \
  рівність-не-обрана; do
  printf -v key '%02d' "$COUNT"
  from="$W/$label"
  cp "$from.sens" "$TEMP/$key.sens"
  cp "$from.expected.sens" "$TEMP/$key.expected.sens"
  cp "$from.elf" "$TEMP/$key.elf"
  cmp "$from.sens" "$TEMP/$key.sens"
  # .lisp — ЛИШЕ pinned укр-проєкція на тих самих фізичних бітах.
  "$UKR" --вивести-ук "$TEMP/$key.sens" "$TEMP/$key.lisp" \
    >"$TEMP/$key.project"
  "$UKR" --пакувати-ук "$TEMP/$key.lisp" "$TEMP/$key.roundtrip.sens" \
    >"$TEMP/$key.pack"
  cmp "$TEMP/$key.sens" "$TEMP/$key.roundtrip.sens" ||
    { echo "ОРАКУЛ-T5M-ПОМИЛКА: укр roundtrip форма=$key" >&2; exit 1; }
  chmod +x "$TEMP/$key.elf"
  timeout 5s "$TEMP/$key.elf" >"$TEMP/$key.machine.sens" \
    2>"$TEMP/$key.machine.err"
  test ! -s "$TEMP/$key.machine.err"
  cmp "$TEMP/$key.expected.sens" "$TEMP/$key.machine.sens"
  # Справжній upstream pinned Rust/Zig SENS REPL, не Pascal evaluator.
  timeout 45s "$ORACLE" --surface=укр <"$TEMP/$key.lisp" \
    >"$TEMP/$key.repl" 2>"$TEMP/$key.repl.err" || {
    echo "ОРАКУЛ-T5M-ПОМИЛКА: незалежний REPL форма=$key" >&2
    cat "$TEMP/$key.repl.err" >&2; exit 1;
  }
  test ! -s "$TEMP/$key.repl.err" ||
    { echo "ОРАКУЛ-T5M-ПОМИЛКА: stderr REPL форма=$key" >&2; exit 1; }
  if ! compare_repl "$TEMP/$key.machine.sens" "$TEMP/$key.repl"; then
    echo "ОРАКУЛ-T5M-ПОМИЛКА: ELF != pinned REPL форма=$key" >&2
    "$T5M" --view "$TEMP/$key.machine.sens" >&2 || true
    cat "$TEMP/$key.repl" >&2
    exit 1
  fi
  bits=$("$T5M" --view "$TEMP/$key.machine.sens")
  case "$bits" in
    0) NO=$((NO+1));;
    1) YES=$((YES+1));;
    000) EMPTY=$((EMPTY+1));;
    *) echo 'ОРАКУЛ-T5M-ПОМИЛКА: неприпустима ширина' >&2; exit 1;;
  esac
  case "$key" in 05|06|07|08) EQ=$((EQ+1));; esac
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 9 && test "$EQ" -eq 4
test "$YES" -ge 1 && test "$NO" -ge 1 && test "$EMPTY" -ge 1
echo "МАШИННИЙ-T5M-REPL-ОРАКУЛ-ГАРАЗД pinned=$PIN фізичних-ELF=$COUNT укр-обернень=$COUNT незалежний-REPL=$COUNT негативів=6 D1:0=$NO D1:1=$YES D3:000=$EMPTY machine-EQ=$EQ"
