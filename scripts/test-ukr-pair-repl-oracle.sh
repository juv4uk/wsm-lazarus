#!/usr/bin/env bash
# G3.23: незалежний SENS REPL є семантичним oracle для фізичних пар укр/.sens.
# Ні FPC evaluator, ні текстова проєкція НЕ визначають мовний закон.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc git timeout awk cmp; do
  command -v "$tool" >/dev/null ||
    { echo "ОРАКУЛ-ПАРИ-БЛОК: потрібен $tool" >&2; exit 127; }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" ||
  { echo 'ОРАКУЛ-ПАРИ-БЛОК: немає зібраного upstream REPL' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" ||
  { echo 'ОРАКУЛ-ПАРИ-БЛОК: upstream SHA не відповідає pinned SENS' >&2; exit 1; }
for law in '(yes . D1:1)' '(no . D1:0)' '(identity . D3:000)' \
  '(atom-result . (D1:0 D1:1))' '(eq-result . (D1:0 D1:1))' \
  '(cond-after-exhaustion . D3:000)'; do
  grep -Fq "$law" external/sens/contracts/language-contract-12.lisp
done
grep -Fq '(0 (ук ні) (укр ні)' external/sens/lib/domains/d1.lisp
grep -Fq '(1 (ук так) (укр так)' external/sens/lib/domains/d1.lisp
grep -Fq '(000 (ук ()) (укр ())' external/sens/lib/domains/d3.lisp

# Старі 36 тестів і всі негативи G3.20/G3.22 залишаються увімкненими.
bash ./scripts/test-ukr-physical-execution.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
FPC_BIN=${FPC:-fpc}
for entry in sensukrvykon sensukrlisp senst5m; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" "-o$entry" "$ROOT/src/$entry.lpr" \
    >"$TMP/compile-$entry.log" 2>&1 || {
      cat "$TMP/compile-$entry.log" >&2; exit 1;
    }
done
RUN="$TMP/bin/sensukrvykon"
PACK="$TMP/bin/sensukrlisp"
VIEW="$TMP/bin/senst5m"

# Переводимо ЛИШЕ відомі ратифіковані result-координати в слова для
# тестового порівнювача. Це не виконавчий dispatch та не numeric plane.
physical_results() {
  "$VIEW" --view "$1" | awk '{
    for (i=1; i<=NF; i++) {
      if ($i == "0") print "НІ";
      else if ($i == "1") print "ТАК";
      else if ($i == "000") print "()";
      else exit 37;
    }
  }'
}

# REPL stdout містить host-prompts; жоден prompt НЕ є частиною SENS.
# Порівнюємо всю ПОСЛІДОВНІСТЬ відповідей, не "хоч один збіг".
repl_results() {
  awk '
    {
      sub(/\r$/, ""); sub(/[ \t]+$/, "");
      line=$0;
      sub(/^sens\[укр\]> /, "", line);
      if (line ~ /(ПОМИЛКА|помилка|ERROR|Error|error)/) bad=1;
      if (line=="НІ" || line=="ТАК" || line=="()") print line;
    }
    END { if (bad) exit 38 }
  ' "$1"
}

compare_repl() {
  local expected="$1" transcript="$2"
  repl_results "$transcript" >"$TMP/normalized" || return 1
  cmp -s "$expected" "$TMP/normalized"
}

# Окремі негативи порівнювача; заборонено приймати зайву/відсутню
# відповідь або "ні" як "так" через частковий grep.
printf 'ТАК\nНІ\n' >"$TMP/comparator.expected"
printf 'sens[укр]> ТАК\nsens[укр]> НІ\n' >"$TMP/comparator.ok"
compare_repl "$TMP/comparator.expected" "$TMP/comparator.ok"
for bad in wrong extra missing empty error; do
  case "$bad" in
    wrong) printf 'sens[укр]> НІ\nsens[укр]> ТАК\n' ;;
    extra) printf 'sens[укр]> ТАК\nsens[укр]> НІ\nsens[укр]> ТАК\n' ;;
    missing) printf 'sens[укр]> ТАК\n' ;;
    empty) printf '' ;;
    error) printf 'sens[укр]> ТАК\nПОМИЛКА: тип\nsens[укр]> НІ\n' ;;
  esac >"$TMP/comparator.$bad"
  if compare_repl "$TMP/comparator.expected" "$TMP/comparator.$bad"; then
    echo "ОРАКУЛ-ПАРИ-ПРОВАЛ: порівнювач прийняв $bad" >&2; exit 1
  fi
done

# Не допускаємо D12 як D1:0 та пошкоджене T5M як oracle-результат.
printf '000000000000\n' >"$TMP/d12.words"
"$VIEW" --pack-words "$TMP/d12.words" >"$TMP/d12.sens"
if physical_results "$TMP/d12.sens" >"$TMP/d12.result"; then
  echo 'ОРАКУЛ-ПАРИ-ПРОВАЛ: ширину D12 прийнято за D1' >&2; exit 1
fi
printf '\363' >"$TMP/broken.sens"
if physical_results "$TMP/broken.sens" >"$TMP/broken.result" 2>"$TMP/broken.err"; then
  echo 'ОРАКУЛ-ПАРИ-ПРОВАЛ: зіпсований T5M прийнято' >&2; exit 1
fi

COUNT=0
check_pair() {
  local label="$1" n="$2"
  "$PACK" --пакувати-ук "$TMP/$label.lisp" "$TMP/$label.sens" \
    >"$TMP/$label.pack.log" 2>"$TMP/$label.pack.err"
  test ! -s "$TMP/$label.pack.err"
  timeout 45s "$RUN" --виконати-пару external/sens "$TMP/$label.lisp" \
    "$TMP/$label.sens" "$TMP/$label.answer.sens" \
    >"$TMP/$label.run.log" 2>"$TMP/$label.run.err" || {
      cat "$TMP/$label.run.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.run.err"
  grep -Fq "УКР-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД форм=$n" "$TMP/$label.run.log"
  grep -Fq 'ПАРА-УКР-ФІЗИЧНО-ПІДТВЕРДЖЕНА' "$TMP/$label.run.log"
  "$VIEW" --перевірити-структуру "$TMP/$label.answer.sens" \
    >"$TMP/$label.structure.log"
  grep -Fq "коренів=$n " "$TMP/$label.structure.log"
  physical_results "$TMP/$label.answer.sens" >"$TMP/$label.expected"
  test "$(wc -l <"$TMP/$label.expected")" -eq "$n"
  # Незалежна семантика — саме upstream SENS REPL, не Pascal reference.
  timeout 60s "$ORACLE" --surface=укр <"$TMP/$label.lisp" \
    >"$TMP/$label.repl" 2>"$TMP/$label.repl.err" || {
      echo "ОРАКУЛ-ПАРИ-ПРОВАЛ: незалежний SENS REPL $label" >&2
      cat "$TMP/$label.repl.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.repl.err" ||
    { cat "$TMP/$label.repl.err" >&2; exit 1; }
  if ! compare_repl "$TMP/$label.expected" "$TMP/$label.repl"; then
    echo "ОРАКУЛ-ПАРИ-ПРОВАЛ: FPC T5M != pinned REPL $label" >&2
    cat "$TMP/$label.expected" "$TMP/$label.repl" >&2; exit 1
  fi
  COUNT=$((COUNT+n))
}

printf 'ні\n' >"$TMP/одна.lisp"
printf 'ні\nтак\n(атом? так)\n(тотожне? ні ні)\n' >"$TMP/чотири.lisp"
for ((i=0;i<64;i++)); do
  if ((i%2==0)); then printf 'ні\n'; else printf 'так\n'; fi
done >"$TMP/шістдесят-чотири.lisp"
printf '(за-умовою (ні так))\n' >"$TMP/порожній-результат.lisp"
check_pair одна 1
check_pair чотири 4
check_pair шістдесят-чотири 64
check_pair порожній-результат 1
test "$COUNT" -eq 70
grep -Fxq '()' "$TMP/порожній-результат.expected"

# Після допуску правильної фізичної пари пізня помилка D3
# не залишає результату і не маскується відповіддю незалежного REPL.
printf 'ні\n(як-є так ні)\n' >"$TMP/пізня.lisp"
"$PACK" --пакувати-ук "$TMP/пізня.lisp" "$TMP/пізня.sens" \
  >"$TMP/пізня.pack.log"
if "$RUN" --виконати-пару external/sens "$TMP/пізня.lisp" \
  "$TMP/пізня.sens" "$TMP/пізня.answer.sens" \
  >"$TMP/пізня.out" 2>"$TMP/пізня.err"; then
  echo 'ОРАКУЛ-ПАРИ-ПРОВАЛ: прийнято пізню семантичну помилку' >&2; exit 1
fi
test ! -s "$TMP/пізня.out"
test ! -e "$TMP/пізня.answer.sens"
grep -Fq 'форма=2' "$TMP/пізня.err"

echo "УКР-ПАРА-НЕЗАЛЕЖНИЙ-REPL-ГАРАЗД pinned=$PIN форми=$COUNT пакети=4 негативів=9 REPL=upstream-semantic-oracle D12+=fail-closed Core4=не-доведено"
