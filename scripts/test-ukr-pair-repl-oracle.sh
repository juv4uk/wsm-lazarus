#!/usr/bin/env bash
# G3.23: незалежний SENS REPL є семантичним oracle для фізичних пар укр/.sens.
# Ні FPC evaluator, ні текстова проєкція НЕ визначають мовний закон.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
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
    diff -u --label "FPC-physical-T5M:$label" --label "pinned-SENS-REPL:$label" \
      "$TMP/$label.expected" "$TMP/normalized" >&2 || true
    # Незалежне встановлення, чи текстові SENS REPL та FPC пакують
    # ОДНАКОВЕ фізичне джерело. Без цього збіг surface не є parity.
    # Діагностика не послаблює cmp: порушення залишається червоним.
    if timeout 90s "$ORACLE" --t5m-mint "$TMP/$label.lisp" \
       "$TMP/$label.upstream.sens" >"$TMP/$label.mint.out" \
       2>"$TMP/$label.mint.err"; then
      if cmp -s "$TMP/$label.sens" "$TMP/$label.upstream.sens"; then
        echo 'ОРАКУЛ-ФІЗИЧНИЙ-ПРОВЕНАНС: upstream-mint збігається з FPC побайтово' >&2
      else
        echo 'ОРАКУЛ-ФІЗИЧНИЙ-ПРОВЕНАНС: upstream-mint НЕ збігається з FPC' >&2
        "$VIEW" --перегляд "$TMP/$label.sens" \
          >"$TMP/$label.fpc.words"
        "$VIEW" --перегляд "$TMP/$label.upstream.sens" \
          >"$TMP/$label.upstream.words"
        echo 'FPC T5M перші 450 символів:' >&2
        head -c 450 "$TMP/$label.fpc.words" >&2; echo >&2
        echo 'upstream Zig T5M перші 450 символів:' >&2
        head -c 450 "$TMP/$label.upstream.words" >&2; echo >&2
        wc -c "$TMP/$label.sens" "$TMP/$label.upstream.sens" >&2
      fi
      if timeout 90s "$ORACLE" --t5m-file "$TMP/$label.lisp" \
        >"$TMP/$label.t5mrun.out" 2>"$TMP/$label.t5mrun.err"; then
        echo 'Незалежне виконання source→Zig-T5M→SENS (останнє значення):' >&2
        tail -n 4 "$TMP/$label.t5mrun.out" >&2
      else
        echo 'Незалежний upstream --t5m-file відхилив програму:' >&2
        tail -n 8 "$TMP/$label.t5mrun.err" >&2
      fi
    else
      echo 'upstream Zig --t5m-mint відхилив джерело:' >&2
      tail -n 8 "$TMP/$label.mint.err" >&2
    fi
    cat "$TMP/$label.expected" "$TMP/$label.repl" >&2; exit 1
  fi
  COUNT=$((COUNT+n))
}

# G3.24: справжній INDEPENDENT pinned SENS evaluator читає ТОЙ САМИЙ
# FPC-generated .sens, root за root. Джерело укр може mint-итися різними
# D2/W7 рамками: схожий текст НЕ є доказом фізичної тотожності.
# Тому цей oracle порівнює результати ЛИШЕ після байтової тотожності входу.
check_physical_pair() {
  local label="$1" n="$2" line answer idx=0
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
  : >"$TMP/$label.independent"
  # Фізичні D2 roots складаються з рівно відповідних single-root
  # T5M документів. Окремий upstream CLI НЕ перепаковує український
  # текст, а одразу виконує ті самі байти SENS через Session::bare().
  while IFS= read -r line || test -n "$line"; do
    idx=$((idx+1))
    printf '%s\n' "$line" >"$TMP/$label-root-$idx.lisp"
    "$PACK" --пакувати-ук "$TMP/$label-root-$idx.lisp" \
      "$TMP/$label-root-$idx.sens" >"$TMP/$label-root-$idx.pack.log"
    timeout 30s "$ORACLE" "$TMP/$label-root-$idx.sens" \
      >"$TMP/$label-root-$idx.value" 2>"$TMP/$label-root-$idx.err" || {
        echo "ОРАКУЛ-ФІЗИЧНИЙ-ПРОВАЛ: $label root=$idx upstream SENS" >&2
        cat "$TMP/$label-root-$idx.err" >&2; exit 1;
      }
    test ! -s "$TMP/$label-root-$idx.err"
    test "$(wc -l <"$TMP/$label-root-$idx.value")" -eq 1
    answer=$(cat "$TMP/$label-root-$idx.value")
    case "$answer" in
      0) printf 'НІ\n' ;;
      1) printf 'ТАК\n' ;;
      '()') printf '()\n' ;;
      *) echo "ОРАКУЛ-ФІЗИЧНИЙ-ПРОВАЛ: невідоме точне слово root=$idx: $answer" >&2; exit 1 ;;
    esac >>"$TMP/$label.independent"
  done <"$TMP/$label.lisp"
  test "$idx" -eq "$n"
  if ! cmp -s "$TMP/$label.expected" "$TMP/$label.independent"; then
    echo "ОРАКУЛ-ФІЗИЧНИЙ-ПРОВАЛ: $label ті самі T5M байти, різні результати" >&2
    diff -u "$TMP/$label.expected" "$TMP/$label.independent" >&2 || true
    exit 1
  fi
  # Негативний КОНТРОЛЬ ПРОЄКЦІЇ: Zig --t5m-mint створює інший
  # фізичний носій із D2:00 / D3:000, тож людський REPL не можна
  # видавати за oracle для FPC-байтів без явної перевірки тотожності.
  timeout 90s "$ORACLE" --t5m-mint "$TMP/$label.lisp" \
    "$TMP/$label.upstream.sens" >"$TMP/$label.mint.log" 2>"$TMP/$label.mint.err" || {
      cat "$TMP/$label.mint.err" >&2; exit 1;
    }
  if cmp -s "$TMP/$label.sens" "$TMP/$label.upstream.sens"; then
    echo 'ОРАКУЛ-ФІЗИЧНИЙ-ПРОВАЛ: очікувана відмінність D2 рамок зникла; звірте тест' >&2
    exit 1
  fi
  timeout 60s "$ORACLE" --surface=укр <"$TMP/$label.lisp" \
    >"$TMP/$label.repl" 2>"$TMP/$label.repl.err" || {
      cat "$TMP/$label.repl.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.repl.err"
  repl_results "$TMP/$label.repl" >"$TMP/$label.normalized"
  # Цей НЕОДНАКОВИЙ текстовий носій має рівно відому відмінність:
  # quoted-так: FPC D1:1, Zig D2/W7 data; решта 15 результатів рівні.
  awk 'NR==15 { if ($0!="ТАК") exit 39; print "НІ"; next } {print}' \
    "$TMP/$label.expected" >"$TMP/$label.text-carrier"
  if ! cmp -s "$TMP/$label.text-carrier" "$TMP/$label.normalized"; then
    echo 'ОРАКУЛ-ФІЗИЧНИЙ-ПРОВАЛ: текстовий REPL має інші розбіжності' >&2
    diff -u "$TMP/$label.text-carrier" "$TMP/$label.normalized" >&2 || true
    exit 1
  fi
  COUNT=$((COUNT+n))
  echo "ФІЗИЧНА-КОМПОЗИЦІЯ-ГАРАЗД форм=$n незалежний-двійковий-SENS=байт-у-байт нееквівалентний-текстовий-носій=окремо"
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

# G3.24: не лише D1 листи, а реальні ВКЛАДЕНІ виклики D3
# із pinned укр проєкції. Семантика визначається тільки upstream REPL;
# FPC виконує ТУ САМУ точну пару фізичних байтів .sens.
cat >"$TMP/вкладені.lisp" <<'КІНЕЦЬ-ВКЛАДЕНИХ'
(атом? (сполучити так ()))
(атом? (сполучити ні ()))
(атом? (перше (сполучити ні ())))
(атом? (решта (сполучити так ())))
(тотожне? (перше (сполучити ні ())) ні)
(тотожне? (перше (сполучити так ())) ні)
(за-умовою ((атом? ні) так))
(за-умовою ((атом? (сполучити так ())) ні) (так так))
(за-умовою ((тотожне? так ні) так) (так ні))
(за-умовою ((тотожне? ні ні) (атом? ні)))
(тотожне? (атом? так) (атом? ні))
(тотожне? (атом? так) (атом? (сполучити ні ())))
(за-умовою ((атом? (сполучити так ())) так))
(атом? (як-є (так ні)))
(атом? (як-є так))
(за-умовою ((тотожне? (атом? ні) так) ні))
КІНЕЦЬ-ВКЛАДЕНИХ
check_physical_pair вкладені 16
test "$(grep -Fxc 'НІ' "$TMP/вкладені.expected")" -ge 3
test "$(grep -Fxc 'ТАК' "$TMP/вкладені.expected")" -ge 3
test "$(grep -Fxc '()' "$TMP/вкладені.expected")" -ge 1
test "$COUNT" -eq 86

# G3.25: не плутати ОДНУ фізичну D3:001 програму із двома
# НЕТОТОЖНИМИ людськими шляхами. Для кожного випадку створюємо
# канонічний T5M двічі: вручну з exact D2+D3+D1 та незалежним FPC
# укр-reader. Лише коли байти ОДНАКОВІ, виконуємо той самий файл
# фізичним FPC та САМОСТІЙНИМ upstream Rust/Zig SENS (Session::bare).
# Обидва значення D1 надалі звіряються за повним текстом і рядками,
# а не за частковим grep. Це НЕ новий evaluator і не закон QUOTE.
QUOTE_COUNT=0
check_exact_quote() {
  local label="$1" source="$2" exact_words="$3" expected="$4" raw
  printf '%s\n' "$source" >"$TMP/$label.lisp"
  printf '%s\n' "$exact_words" >"$TMP/$label.words"
  "$VIEW" --pack-words "$TMP/$label.words" >"$TMP/$label.manual.sens"
  "$PACK" --пакувати-ук "$TMP/$label.lisp" "$TMP/$label.sens" \
    >"$TMP/$label.pack.log" 2>"$TMP/$label.pack.err"
  test ! -s "$TMP/$label.pack.err"
  if ! cmp -s "$TMP/$label.manual.sens" "$TMP/$label.sens"; then
    echo "ОРАКУЛ-ЦИТАТА-ПРОВАЛ: $label FPC укр не збігається з exact T5M" >&2
    exit 1
  fi
  timeout 45s "$RUN" --виконати-пару external/sens "$TMP/$label.lisp" \
    "$TMP/$label.sens" "$TMP/$label.answer.sens" \
    >"$TMP/$label.run.log" 2>"$TMP/$label.run.err" || {
      cat "$TMP/$label.run.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.run.err"
  grep -Fq 'УКР-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД форм=1' "$TMP/$label.run.log"
  grep -Fq 'ПАРА-УКР-ФІЗИЧНО-ПІДТВЕРДЖЕНА' "$TMP/$label.run.log"
  "$VIEW" --перевірити-структуру "$TMP/$label.answer.sens" \
    >"$TMP/$label.structure.log"
  grep -Fq 'коренів=1 ' "$TMP/$label.structure.log"
  physical_results "$TMP/$label.answer.sens" >"$TMP/$label.physical"
  printf '%s\n' "$expected" >"$TMP/$label.expected"
  if ! cmp -s "$TMP/$label.expected" "$TMP/$label.physical"; then
    echo "ОРАКУЛ-ЦИТАТА-ПРОВАЛ: $label фізична FPC-відповідь" >&2
    diff -u "$TMP/$label.expected" "$TMP/$label.physical" >&2 || true
    exit 1
  fi
  timeout 45s "$ORACLE" "$TMP/$label.sens" \
    >"$TMP/$label.upstream" 2>"$TMP/$label.upstream.err" || {
      echo "ОРАКУЛ-ЦИТАТА-ПРОВАЛ: $label pinned binary SENS" >&2
      cat "$TMP/$label.upstream.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.upstream.err"
  case "$expected" in
    ТАК) raw=1 ;;
    НІ) raw=0 ;;
    *) echo 'ОРАКУЛ-ЦИТАТА-ПРОВАЛ: недопущений результат D1' >&2; exit 1 ;;
  esac
  printf '%s\n' "$raw" >"$TMP/$label.expected-upstream"
  if ! cmp -s "$TMP/$label.expected-upstream" "$TMP/$label.upstream"; then
    echo "ОРАКУЛ-ЦИТАТА-ПРОВАЛ: $label SAME .sens bytes != upstream" >&2
    diff -u "$TMP/$label.expected-upstream" "$TMP/$label.upstream" >&2 || true
    exit 1
  fi
  QUOTE_COUNT=$((QUOTE_COUNT+1))
}

# Чотири справжні pinned exact program: пряма цитата D1:1 / D1:0
# і композиція того самого D3:001 з ATOM. Немає D7 у функціональній
# позиції, немає host truthiness або числа D12 замість D1.
check_exact_quote точна-цитата-так '(як-є так)' \
  '10 001 1 01' 'ТАК'
check_exact_quote точна-цитата-ні '(як-є ні)' \
  '10 001 0 01' 'НІ'
check_exact_quote атом-цитати-так '(атом? (як-є так))' \
  '10 010 10 001 1 01 01' 'ТАК'
check_exact_quote атом-цитати-ні '(атом? (як-є ні))' \
  '10 010 10 001 0 01 01' 'ТАК'
test "$QUOTE_COUNT" -eq 4

# Негативний контроль: у pinned SENS текстовий REPL із тих самих
# ЛІТЕР друкує D7 послідовність, тоді як ФІЗИЧНИЙ D3:001 вище
# повернув точне D1:1. Це різні програми, НЕ semantic mismatch
# одного і того самого канонічного .sens.
timeout 60s "$ORACLE" --surface=укр \
  <"$TMP/точна-цитата-так.lisp" \
  >"$TMP/точна-цитата-так.text-repl" \
  2>"$TMP/точна-цитата-так.text-repl.err"
test ! -s "$TMP/точна-цитата-так.text-repl.err"
awk '
  { sub(/\r$/, ""); line=$0; sub(/^sens\[укр\]> /,"",line);
    if (line=="(т а к)") found++;
    if (line=="ТАК" || line=="НІ") wrong++;
  }
  END { if (found!=1 || wrong) exit 41 }
' "$TMP/точна-цитата-так.text-repl" || {
  echo 'ОРАКУЛ-ЦИТАТА-ПРОВАЛ: текстовий upstream REPL drift D7' >&2
  cat "$TMP/точна-цитата-так.text-repl" >&2; exit 1
}
timeout 90s "$ORACLE" --t5m-mint \
  "$TMP/точна-цитата-так.lisp" "$TMP/точна-цитата-так.upstream-mint.sens" \
  >"$TMP/точна-цитата-так.mint.log" \
  2>"$TMP/точна-цитата-так.mint.err"
test ! -s "$TMP/точна-цитата-так.mint.err"
if cmp -s "$TMP/точна-цитата-так.sens" \
  "$TMP/точна-цитата-так.upstream-mint.sens"; then
  echo 'ОРАКУЛ-ЦИТАТА-ПРОВАЛ: фізичні носії несподівано стали тотожні' >&2
  exit 1
fi
echo "ЦИТАТА-ОДНАКОВИЙ-T5M-ГАРАЗД випадків=$QUOTE_COUNT FPC=real upstream=real D1=exact фізичний-файл=тотожний текстовий-D7-носій=інший"


# Відхилення EQ-із-парою саме на вкладеному фізичному виклику:
# жодної часткової відповіді, точний 1-based номер пізньої форми.
printf 'ні\n(тотожне? (сполучити ні ()) ні)\n' \
  >"$TMP/вкладена-помилка.lisp"
"$PACK" --пакувати-ук "$TMP/вкладена-помилка.lisp" \
  "$TMP/вкладена-помилка.sens" >"$TMP/вкладена-помилка.pack.log"
if "$RUN" --виконати-пару external/sens \
  "$TMP/вкладена-помилка.lisp" "$TMP/вкладена-помилка.sens" \
  "$TMP/вкладена-помилка.answer.sens" \
  >"$TMP/вкладена-помилка.out" 2>"$TMP/вкладена-помилка.err"; then
  echo 'ОРАКУЛ-ПАРИ-ПРОВАЛ: вкладену помилку EQ прийнято' >&2
  exit 1
fi
test ! -s "$TMP/вкладена-помилка.out"
test ! -e "$TMP/вкладена-помилка.answer.sens"
grep -Fq 'форма=2' "$TMP/вкладена-помилка.err"

# Справжній новий файловий запуск ПІСЛЯ помилки, не stale-output.
printf '(атом? (сполучити ні ()))\n' >"$TMP/після-помилки.lisp"
check_pair після-помилки 1
test "$COUNT" -eq 87
test "$(cat "$TMP/після-помилки.expected")" = 'НІ'

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

echo "УКР-ПАРА-НЕЗАЛЕЖНИЙ-REPL-ГАРАЗД pinned=$PIN форми=$COUNT пакети=6 вкладених=16 негативів=10 REPL=upstream-semantic-oracle binary=upstream-same-T5M D12+=fail-closed Core4=не-доведено"
