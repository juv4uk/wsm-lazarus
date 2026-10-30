#!/usr/bin/env bash
# G6.44 — незалежний фізичний oracle для СПРАВЖНЬОГО Linux ELF64.
# Ті САМІ pinned .sens байти запускають машинний FPC та upstream SENS.
# Людська укр/.lisp — проєкція, не джерело цього семантичного доказу.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
FPC_BIN=${FPC:-fpc}
for tool in "$FPC_BIN" git timeout cmp; do
  command -v "$tool" >/dev/null || { echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-БЛОК: бракує $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || { echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-БЛОК: upstream SENS не зібрано' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-БЛОК: змінено pinned SENS SHA' >&2; exit 1;
}
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(000 (ук ()) (укр ())' external/sens/lib/domains/d3.lisp
grep -Fq '0010110 — SYN' external/sens/lib/domains/d7.lisp

# ЖОДНОГО вимкненого gate: перед independent oracle виконуємо
# наявні фізичні ELF/відмови/no-clobber/geometry regressions.
timeout 240s bash ./scripts/test-senselfvykon.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/witnesses"
for entry in 'src/senselfvykon.lpr senselfvykon' \
  'scripts/test-senselfvykon.pas test-senselfvykon' \
  'src/senst5m.lpr senst5m'; do
  read -r path bin <<< "$entry"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" "$ROOT/$path" \
    >"$TMP/build-$bin.log" 2>&1 || { cat "$TMP/build-$bin.log" >&2; exit 1; }
done
timeout 15s "$TMP/bin/test-senselfvykon" "$TMP/witnesses" \
  >"$TMP/witnesses.log" 2>"$TMP/witnesses.err"
test ! -s "$TMP/witnesses.err" || grep -F '0 unfreed memory blocks' "$TMP/witnesses.err" >/dev/null
CLI="$TMP/bin/senselfvykon"
VIEW="$TMP/bin/senst5m"

# Тільки точна D1:0, D1:1, D3:000 відповідь. D12 числа, W7 SYN
# або два D2 корені НЕ можна мовчки перетворювати на host bool.
exact_result() {
  local bits
  bits=$("$VIEW" --view "$1") || return 1
  case "$bits" in
    0|1) printf '%s\n' "$bits" ;;
    000) printf '()\n' ;;
    *) return 1 ;;
  esac
}
same_answer() {
  local expected_file="$1" actual_file="$2"
  cmp -s "$expected_file" "$actual_file"
}

# Шість негативів компаратора; навіть правильна перша стрічка
# плюс зайва/пізня відповідь або помилка виводу — не parity.
NEG=0
printf '1\n' >"$TMP/expected.oracle"
printf '1\n' >"$TMP/ok.oracle"
same_answer "$TMP/expected.oracle" "$TMP/ok.oracle"
for bad in wrong extra absent empty error; do
  case "$bad" in
    wrong) printf '0\n' ;;
    extra) printf '1\n0\n' ;;
    absent|empty) printf '' ;;
    error) printf '1\nПОМИЛКА: інша відповідь\n' ;;
  esac >"$TMP/$bad.oracle"
  if same_answer "$TMP/expected.oracle" "$TMP/$bad.oracle"; then
    echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: компаратор прийняв $bad" >&2; exit 1
  fi
  NEG=$((NEG+1))
done
printf '000000000000\n' >"$TMP/d12.words"
"$VIEW" --pack-words "$TMP/d12.words" >"$TMP/d12.sens"
if exact_result "$TMP/d12.sens" >"$TMP/d12.normal"; then
  echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: D12 став D1' >&2; exit 1
fi
NEG=$((NEG+1))
printf '0 1\n' >"$TMP/two.words"
"$VIEW" --pack-words "$TMP/two.words" >"$TMP/two.sens"
if exact_result "$TMP/two.sens" >"$TMP/two.normal"; then
  echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: дві D2 відповіді стали однією' >&2; exit 1
fi
NEG=$((NEG+1))
printf '\363' >"$TMP/corrupt.sens"
if exact_result "$TMP/corrupt.sens" >"$TMP/corrupt.normal" 2>"$TMP/corrupt.err"; then
  echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: неканонічний T5M допущено' >&2; exit 1
fi
NEG=$((NEG+1))
test "$NEG" -eq 8

COUNT=0; QUOTES=0; ATOMS=0; EQUALS=0; SELECTORS=0; CONDITIONS=0
check_same_physical() {
  local mode="$1" label="$2"
  local src="$TMP/witnesses/$label.sens" out="$TMP/$label.machine.sens"
  # Головна інваріанта: обидва незалежні виконавці бачать
  # один і той самий readonly source, без текстового mint.
  test -s "$src"
  timeout 14s "$CLI" "--$mode" external/sens "$src" "$out" \
    >"$TMP/$label.elf.out" 2>"$TMP/$label.elf.err" || {
      echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: машинний ELF $label" >&2
      cat "$TMP/$label.elf.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.elf.err" || grep -F '0 unfreed memory blocks' "$TMP/$label.elf.err" >/dev/null
  test -s "$out"
  cmp "$out" "$TMP/witnesses/$label.expected.sens" || {
    echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: неправильний T5M ELF $label" >&2; exit 1;
  }
  "$VIEW" --перевірити-структуру "$out" >"$TMP/$label.structure"
  grep -Fq 'коренів=1 ' "$TMP/$label.structure"
  exact_result "$out" >"$TMP/$label.expected.oracle" || {
    echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: D1/D3 результат $label" >&2; exit 1;
  }
  timeout 60s "$ORACLE" "$src" >"$TMP/$label.upstream.oracle" \
    2>"$TMP/$label.upstream.err" || {
      echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: pinned SENS $label" >&2
      cat "$TMP/$label.upstream.err" >&2; exit 1;
    }
  test ! -s "$TMP/$label.upstream.err" || {
    echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: stderr upstream $label" >&2
    cat "$TMP/$label.upstream.err" >&2; exit 1;
  }
  if ! same_answer "$TMP/$label.expected.oracle" "$TMP/$label.upstream.oracle"; then
    echo "ФІЗИЧНИЙ-ELF-ОРАКУЛ-РОЗБІЖНІСТЬ: профіль=$mode форма=$label pinned=$PIN" >&2
    echo '--- точний T5M вхід ---' >&2
    "$VIEW" --view "$src" >&2 || :
    echo '--- фізична відповідь ELF ---' >&2
    cat "$TMP/$label.expected.oracle" >&2
    echo '--- незалежний pinned SENS ---' >&2
    cat "$TMP/$label.upstream.oracle" >&2
    exit 1
  fi
  COUNT=$((COUNT+1))
  case "$mode" in
    цитата) QUOTES=$((QUOTES+1));;
    атом) ATOMS=$((ATOMS+1));;
    тотожність) EQUALS=$((EQUALS+1));;
    селектор) SELECTORS=$((SELECTORS+1));;
    умова) CONDITIONS=$((CONDITIONS+1));;
    *) echo 'ФІЗИЧНИЙ-ELF-ОРАКУЛ-ПРОВАЛ: host профіль' >&2; exit 1 ;;
  esac
}

# p01: D7 SYN фізично цитований 7-бітний контрольний символ;
# НЕ перейменовуємо його на D1 і НЕ виводимо фальшивий укр REPL.
# p02..p10: реальні ратифіковані фізичні виходи D1/D3.
for record in 'цитата:p02' 'атом:p03' 'атом:p04' \
  'тотожність:p05' 'тотожність:p06' \
  'селектор:p07' 'селектор:p08' \
  'умова:p09' 'умова:p10'; do
  IFS=: read -r mode label <<< "$record"
  check_same_physical "$mode" "$label"
done
test "$COUNT" -eq 9
test "$QUOTES" -eq 1 && test "$ATOMS" -eq 2 &&
test "$EQUALS" -eq 2 && test "$SELECTORS" -eq 2 &&
test "$CONDITIONS" -eq 2
echo "МАШИНА-НЕЗАЛЕЖНИЙ-БІНАРНИЙ-SENS-ГАРАЗД pinned=$PIN Linux-x86_64-ELF=$COUNT п'ять-профілів=так фізичний-T5M=той-самий D1/D3=точний негативів=$NEG D7-SYN=не-D1 текстовий-REPL=окремий"
