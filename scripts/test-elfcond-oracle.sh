#!/usr/bin/env bash
# G6.23 — 32 однакові фізичні .sens: machine ELF64 проти справжнього
# незалежного pinned SENS REPL; .lisp є тільки оберненою укр-проєкцією.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЕЛФ-ОРАКУЛ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
command -v fpc >/dev/null
command -v readelf >/dev/null
command -v timeout >/dev/null
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || { echo 'ЕЛФ-ОРАКУЛ-БЛОК: не зібрано незалежний SENS REPL' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47 || {
  echo 'ЕЛФ-ОРАКУЛ-БЛОК: невідповідний pin upstream REPL' >&2; exit 1;
}

# Чинний FPC test-elfcond.pas фізично створює ці 32 .sens і запускає
# кожний ELF, 26 негативних форм, порівнює з існуючим FPC sensvykon.
# Цей самостійний тест НЕ використовує sensvykon як свій oracle.
bash ./scripts/test-elfcond.sh

mkdir -p build/m0.2/elfcond-oracle/units build/m0.2/elfcond-oracle/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/elfcond-oracle/units" \
  -FE"$ROOT/build/m0.2/elfcond-oracle/bin" \
  -osensukrlisp "$ROOT/src/sensukrlisp.lpr"
UKR="$ROOT/build/m0.2/elfcond-oracle/bin/sensukrlisp"
BACKEND="$ROOT/build/m0.2/elfcond/bin/senscondelf"
test -x "$UKR" && test -x "$BACKEND"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Поверхня повністю утворена з pinned таблиць D1–D9 програмою
# PhysicalToUkrainian. Тут немає ручного English/Lisp dispatch.
# Кореневий SENS REPL незалежно тлумачить отриману українську форму.
check_result() {
  local label="$1" machine="$2" actual expected
  actual=$(cat "$machine")
  case "$actual" in
    0) expected='НІ' ;;
    1) expected='ТАК' ;;
    '()') expected='()' ;;
    *) echo "ЕЛФ-ОРАКУЛ-ПРОВАЛ: неочікуваний фізичний stdout: $label" >&2; exit 1 ;;
  esac
  if ! awk -v wanted="$expected" '
    { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
    $0 == wanted || $0 == "sens[укр]> " wanted { hits++ }
    END { exit (hits == 1 ? 0 : 1) }
  ' "$TMP/$label.repl"; then
    echo "ЕЛФ-ОРАКУЛ-ПРОВАЛ: $label ELF=$actual SENS-REPL-очікувано=$expected" >&2
    cat "$TMP/$label.repl" >&2
    exit 1
  fi
}

# Синтетичний негативний контроль самого порівнювача:
# відповідь «НІ» не має проходити як «ТАК».
printf 'sens[укр]> НІ\n' > "$TMP/помилкова-відповідь"
if awk -v wanted='ТАК' '
  { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
  $0 == wanted || $0 == "sens[укр]> " wanted { hits++ }
  END { exit (hits == 1 ? 0 : 1) }
' "$TMP/помилкова-відповідь"; then
  echo 'ЕЛФ-ОРАКУЛ-ПРОВАЛ: порівнювач приймає хибну відповідь' >&2
  exit 1
fi

COUNT=0
for label in \
  без-гілок одна-істинна одна-істинна-ні одна-хибна \
  дві-друга-істинна дві-перша-істинна дві-хибні \
  три-остання-істинна три-вичерпано \
  шістнадцять-остання-істинна шістнадцять-вичерпано \
  тридцять-дві-остання-істинна тридцять-дві-перша-істинна \
  тридцять-дві-вичерпано \
  рівність-00 рівність-01 рівність-10 рівність-11 \
  дві-рівності-друга дві-рівності-перша \
  тридцять-дві-рівності тридцять-дві-рівності-порожньо \
  вираз-рівність-00 вираз-рівність-01 вираз-рівність-10 вираз-рівність-11 \
  вираз-хибна-гілка вираз-друга-гілка вираз-перша-гілка \
  вираз-тест-і-відповідь вираз-хибний-тест-рівність \
  вираз-тридцять-дві-рівності; do
  INPUT="$ROOT/build/m0.2/elfcond/$label.sens"
  test -s "$INPUT"
  "$UKR" --вивести-ук "$INPUT" "$TMP/$label.lisp" >"$TMP/$label.project"
  test "$(wc -l <"$TMP/$label.lisp")" -eq 1
  "$UKR" --пакувати-ук "$TMP/$label.lisp" "$TMP/$label.roundtrip.sens" \
    >"$TMP/$label.pack"
  cmp "$INPUT" "$TMP/$label.roundtrip.sens" || {
    echo "ЕЛФ-ОРАКУЛ-ПРОВАЛ: порушено фізичний round-trip $label" >&2; exit 1;
  }
  "$BACKEND" --породити "$INPUT" "$TMP/$label.elf" >"$TMP/$label.compile"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.elfhdr"
  grep -Fq 'EXEC (Executable file)' "$TMP/$label.elfhdr"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.machine"
  # Це справжній pinned Rust/Zig REPL; FPC не створює тут expected value.
  timeout 45s "$ORACLE" --surface=укр <"$TMP/$label.lisp" \
    >"$TMP/$label.repl" 2>"$TMP/$label.err" || {
      echo "ЕЛФ-ОРАКУЛ-ПРОВАЛ: pinned upstream REPL $label" >&2
      cat "$TMP/$label.err" >&2
      exit 1
    }
  if test -s "$TMP/$label.err"; then
    echo "ЕЛФ-ОРАКУЛ-ПРОВАЛ: stderr pinned upstream REPL $label" >&2
    cat "$TMP/$label.err" >&2
    exit 1
  fi
  check_result "$label" "$TMP/$label.machine"
  COUNT=$((COUNT+1))
done

test "$COUNT" -eq 32
# Відокремлений негативний фізичний вхід не публікує проєкцію.
printf '\363' >"$TMP/зіпсований.sens"
if "$UKR" --вивести-ук "$TMP/зіпсований.sens" "$TMP/хибне.lisp" \
  >"$TMP/негатив.out" 2>"$TMP/негатив.err"; then
  echo 'ЕЛФ-ОРАКУЛ-ПРОВАЛ: пошкоджений T5M спроєктовано' >&2
  exit 1
fi
test ! -e "$TMP/хибне.lisp"
test ! -s "$TMP/негатив.out"
echo "ЕЛФ-REPL-ОРАКУЛ-ГАРАЗД pinned=2c498b35af53c085450eac6f51b87facf7f9aa47 фізичних-ELF=$COUNT український-roundtrip=байт-у-байт REPL=незалежний негативні=26"
