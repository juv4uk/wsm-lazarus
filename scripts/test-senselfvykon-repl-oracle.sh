#!/usr/bin/env bash
# G6.41 — РЕАЛЬНА незалежна semantic REPL parity для файлового ELF/T5M.
# Єдині мовні закони — pinned external/sens, НЕ власний Pascal comparator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc git timeout cmp awk readelf; do
  command -v "$tool" >/dev/null || {
    echo "МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: лише Linux x86-64' >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: немає upstream REPL' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: upstream SHA не pinned' >&2; exit 1;
}
for law in '(yes . D1:1)' '(no . D1:0)' '(identity . D3:000)' \
  '(atom-result . (D1:0 D1:1))' '(eq-result . (D1:0 D1:1))' \
  '(cond-after-exhaustion . D3:000)'; do
  grep -Fq "$law" external/sens/contracts/language-contract-12.lisp
done
grep -Fq '(000 (ук ()) (укр ())' external/sens/lib/domains/d3.lisp
grep -Fq '128 із 128 семибітних координат' external/sens/lib/domains/d7.lisp

# Не скасовуємо жоден існуючий негатив чи byte-exact фізичний доказ.
timeout 210s bash ./scripts/test-senselfvykon.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/witnesses"
FPC_BIN=${FPC:-fpc}
for entry in 'src/senselfvykon.lpr senselfvykon' \
  'scripts/test-senselfvykon.pas test-senselfvykon' \
  'src/sensukrlisp.lpr sensukrlisp' \
  'src/senst5m.lpr senst5m'; do
  read -r path bin <<< "$entry"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" "$ROOT/$path" \
    >"$TMP/$bin.build.log" 2>&1 || {
      cat "$TMP/$bin.build.log" >&2; exit 1;
    }
done
timeout 15s "$TMP/bin/test-senselfvykon" "$TMP/witnesses" \
  >"$TMP/witnesses.log"
CLI="$TMP/bin/senselfvykon"
UKR="$TMP/bin/sensukrlisp"
VIEW="$TMP/bin/senst5m"

# Тестовий компаратор має прийняти РІВНО ОДНУ завершену
# REPL-відповідь; не допускаємо "хоч один збіг" поряд із зайвим.
normal_repl() {
  awk '
    {
      sub(/\r$/, ""); sub(/[ \t]+$/, "");
      line=$0;
      sub(/^sens\[укр\]> /, "", line);
      if (line ~ /(ПОМИЛКА|помилка|ERROR|Error|error)/) bad=1;
      if (line=="НІ" || line=="ТАК" || line=="()") print line;
    }
    END { if (bad) exit 48 }
  ' "$1"
}
physical_to_compare() {
  local bits
  bits=$("$VIEW" --view "$1") || return 1
  case "$bits" in
    0) printf 'НІ\n' ;;
    1) printf 'ТАК\n' ;;
    000) printf '()\n' ;;
    *) return 1 ;;
  esac
}
compare_repl() {
  local physical="$1" transcript="$2"
  physical_to_compare "$physical" >"$TMP/expected.normal" || return 1
  normal_repl "$transcript" >"$TMP/actual.normal" || return 1
  cmp -s "$TMP/expected.normal" "$TMP/actual.normal"
}

# Негативи самого семантичного comparator (не правити очікувану
# відповідь заради зеленої машини). Відмова і на зайве/порожнє.
printf '1\n' >"$TMP/yes.words"
"$VIEW" --pack-words "$TMP/yes.words" >"$TMP/yes.sens"
printf 'sens[укр]> ТАК\n' >"$TMP/correct"
compare_repl "$TMP/yes.sens" "$TMP/correct"
NEG=0
for case_name in wrong extra missing empty error; do
  case "$case_name" in
    wrong) printf 'sens[укр]> НІ\n' ;;
    extra) printf 'sens[укр]> ТАК\nsens[укр]> НІ\n' ;;
    missing|empty) printf '' ;;
    error) printf 'sens[укр]> ТАК\nПОМИЛКА: тип\n' ;;
  esac >"$TMP/$case_name"
  if compare_repl "$TMP/yes.sens" "$TMP/$case_name"; then
    echo "МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-ПРОВАЛ: comparator=$case_name" >&2; exit 1
  fi
  NEG=$((NEG+1))
done
printf '000000000000\n' >"$TMP/d12.words"
"$VIEW" --pack-words "$TMP/d12.words" >"$TMP/d12.sens"
if compare_repl "$TMP/d12.sens" "$TMP/correct"; then
  echo 'МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-ПРОВАЛ: D12 прийнятий як D1' >&2; exit 1
fi
NEG=$((NEG+1))
printf '0 1\n' >"$TMP/two.words"
"$VIEW" --pack-words "$TMP/two.words" >"$TMP/two.sens"
if compare_repl "$TMP/two.sens" "$TMP/correct"; then
  echo 'МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-ПРОВАЛ: дві відповіді як одна' >&2; exit 1
fi
NEG=$((NEG+1))
printf '\363' >"$TMP/damaged.sens"
if compare_repl "$TMP/damaged.sens" "$TMP/correct" 2>"$TMP/damaged.err"; then
  echo 'МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-ПРОВАЛ: пошкоджений T5M' >&2; exit 1
fi
NEG=$((NEG+1))
test "$NEG" -eq 8

# Єдиний вхід до upstream REPL — з pinned УКР, який повертає
# ТОЧНО ті ж binary T5M байти. Жодного ручного англійського
# або ASCII тексту у викличних позиціях.
COUNT=0
ATTEMPTS=0
MISMATCHES=0
QUOTES=0 ATOMS=0 EQUALS=0 SELECTORS=0 CONDITIONS=0
check_form() {
  local mode="$1" label="$2"
  local src="$TMP/witnesses/$label.sens" out="$TMP/$label.machine.sens"
  ATTEMPTS=$((ATTEMPTS+1))
  "$UKR" --вивести-ук "$src" "$TMP/$label.lisp" \
    >"$TMP/$label.project.log" 2>"$TMP/$label.project.err" || {
      echo "ОРАКУЛ-ПРОВАЛ: необоротна проєкція $label" >&2
      cat "$TMP/$label.project.err" >&2; exit 1;
    }
  "$UKR" --пакувати-ук "$TMP/$label.lisp" "$TMP/$label.round.sens" \
    >"$TMP/$label.round.log" 2>"$TMP/$label.round.err"
  cmp "$src" "$TMP/$label.round.sens" || {
    echo "ОРАКУЛ-ПРОВАЛ: втрачено двійковий canonical round-trip $label" >&2
    exit 1
  }
  timeout 12s "$CLI" "--$mode" external/sens "$src" "$out" \
    >"$TMP/$label.run.log" 2>"$TMP/$label.run.err" || {
      echo "ОРАКУЛ-ПРОВАЛ: native ELF $label" >&2
      cat "$TMP/$label.run.err" >&2; exit 1
    }
  cmp "$out" "$TMP/witnesses/$label.expected.sens"
  timeout 60s "$ORACLE" --surface=укр <"$TMP/$label.lisp" \
    >"$TMP/$label.repl" 2>"$TMP/$label.repl.err" || {
      echo "ОРАКУЛ-ПРОВАЛ: independent pinned SENS REPL $label" >&2
      cat "$TMP/$label.repl.err" >&2; exit 1
    }
  test ! -s "$TMP/$label.repl.err" || {
    echo "ОРАКУЛ-ПРОВАЛ: REPL stderr $label" >&2
    cat "$TMP/$label.repl.err" >&2; exit 1
  }
  if ! compare_repl "$out" "$TMP/$label.repl"; then
    echo "ОРАКУЛ-РОЗБІЖНІСТЬ: форма=$label host-профіль=$mode pinned-SENS=$PIN" >&2
    echo '--- точна оборотна укр проєкція (REPL stdin) ---' >&2
    cat "$TMP/$label.lisp" >&2
    echo '--- фізична машинна відповідь (exact bits) ---' >&2
    "$VIEW" --view "$out" >&2 || :
    echo '--- дослівний незалежний upstream REPL stdout ---' >&2
    cat "$TMP/$label.repl" >&2
    MISMATCHES=$((MISMATCHES+1))
  else
    COUNT=$((COUNT+1))
  fi
  case "$mode" in
    цитата) QUOTES=$((QUOTES+1));;
    атом) ATOMS=$((ATOMS+1));;
    тотожність) EQUALS=$((EQUALS+1));;
    селектор) SELECTORS=$((SELECTORS+1));;
    умова) CONDITIONS=$((CONDITIONS+1));;
  esac
}

# D7 SYN p01 — семибітні контрольні ДАНІ, для нього немає
# оборотної друкованої "укр"; НЕ малюємо фальшивий текст REPL.
if "$UKR" --вивести-ук "$TMP/witnesses/p01.sens" "$TMP/no-syn.lisp" \
  >"$TMP/syn.out" 2>"$TMP/syn.err"; then
  echo 'ОРАКУЛ-ПРОВАЛ: непроєктовний D7 SYN прийнято як укр атом' >&2; exit 1
fi
test ! -e "$TMP/no-syn.lisp"
test ! -s "$TMP/syn.out"
NEG=$((NEG+1))

# D3:000 не тотожне D1:0 і не має окремого текстового атома.
if "$UKR" --вивести-ук "$TMP/witnesses/p04.sens" "$TMP/no-d3000.lisp" \
  >"$TMP/d3000.out" 2>"$TMP/d3000.err"; then
  echo 'ОРАКУЛ-ПРОВАЛ: непроєктовне D3:000 видано за укр атом' >&2; exit 1
fi
test ! -e "$TMP/no-d3000.lisp"
test ! -s "$TMP/d3000.out"
NEG=$((NEG+1))

check_form цитата p02
check_form атом p03
check_form тотожність p05
check_form тотожність p06
check_form селектор p07
check_form селектор p08
check_form умова p09
check_form умова p10

test "$ATTEMPTS" -eq 8
test "$QUOTES" -eq 1 && test "$ATOMS" -eq 1 &&
test "$EQUALS" -eq 2 && test "$SELECTORS" -eq 2 &&
test "$CONDITIONS" -eq 2 && test "$NEG" -eq 10
if (( MISMATCHES > 0 )); then
  echo "МАШИННИЙ-ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: pinned-SENS=$PIN machine-vs-upstream-mismatches=$MISMATCHES/$ATTEMPTS збігів=$COUNT. НІЧОГО НЕ ЗЛИВАТИ без семантичного виправлення." >&2
  exit 1
fi
test "$COUNT" -eq "$ATTEMPTS"
echo "МАШИННИЙ-ФАЙЛОВИЙ-ПІННЕД-REPL-ГАРАЗД pin=$PIN Linux-ELF=$COUNT укр-roundtrip=$COUNT independent-SENS-REPL=$COUNT comparator-негативи=$NEG усі-пять-профілів=так D7-SYN=лише-дані"
