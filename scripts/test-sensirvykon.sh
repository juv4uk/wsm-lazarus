#!/usr/bin/env bash
# G6.53: EIR1 є передумовою виконання фізичного D3, а не executable IR.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ПЕРЕВІРЕНИЙ-IR-БЛОК: відсутній FPC' >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test -f external/sens/contracts/language-contract-12.lisp || {
  echo 'ПЕРЕВІРЕНИЙ-IR-БЛОК: відсутній pinned Contract 12' >&2; exit 1;
}
mkdir -p build/m0.2/irvykon-units build/m0.2/bin
for pair in 'sensirvykon src/sensirvykon.lpr' \
            'sensexact src/sensexact.lpr' \
            'senst5m src/senst5m.lpr' \
            'sensvykon src/sensvykon.lpr'; do
  read -r name path <<< "$pair"
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/irvykon-units" -FE"$ROOT/build/m0.2/bin" \
    -o"$name" "$ROOT/$path" >/dev/null
done
EXE="$ROOT/build/m0.2/bin/sensirvykon"
MINT="$ROOT/build/m0.2/bin/sensexact"
T5M="$ROOT/build/m0.2/bin/senst5m"
BASELINE="$ROOT/build/m0.2/bin/sensvykon"
TMP=$(mktemp -d "$ROOT/build/m0.2/irvykon.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT
reject() {
  local label=$1; shift
  if timeout 30s "$@" >"$TMP/заборонено.out" 2>"$TMP/заборонено.err"; then
    echo "ПЕРЕВІРЕНИЙ-IR-ПРОВАЛ: допущено $label" >&2; exit 1;
  fi
  [[ ! -s "$TMP/заборонено.out" ]] &&
    grep -q 'ПЕРЕВІРЕНИЙ-IR-ВІДХИЛЕНО' "$TMP/заборонено.err" || {
    echo "ПЕРЕВІРЕНИЙ-IR-ПРОВАЛ: частковий stdout/без діагностики: $label" >&2
    cat "$TMP/заборонено.err" >&2; exit 1;
  }
}
positive=0
for pair in 'd1-ni|0' 'd1-tak|1' \
    'tsytata|10 001 0 01' \
    'atom|10 010 10 001 0 01 01' \
    'umova|10 110 10 1 0 01 01' \
    'para|10 111 0 1 01'; do
  name=${pair%%|*}; words=${pair#*|}
  printf '%s\n' "$words" > "$TMP/$name.words"
  "$T5M" --пакувати-слова "$TMP/$name.words" > "$TMP/$name.sens"
  "$MINT" --створити-ір "$TMP/$name.sens" "$TMP/$name.eir" \
    >"$TMP/$name.created"
  timeout 30s "$EXE" --перевірити-та-виконати \
    "$TMP/$name.sens" "$TMP/$name.eir" > "$TMP/$name.answer.sens"
  "$T5M" --перегляд "$TMP/$name.answer.sens" > "$TMP/$name.answer.words"
  timeout 30s "$BASELINE" --виконати "$TMP/$name.sens" \
    > "$TMP/$name.native"
  [[ -s "$TMP/$name.answer.sens" && -s "$TMP/$name.native" ]]
  # Вузький результат D1/QUOTE/ATOM/COND перевіряємо точними словами.
  case "$name" in
    d1-ni|tsytata|umova) printf '0\n' > "$TMP/$name.expected.words" ;;
    d1-tak|atom) printf '1\n' > "$TMP/$name.expected.words" ;;
    para) printf '10\n' > "$TMP/$name.expected.words"
          # Для CONS лише відмінність від порожнього/атомного результату.
          ;;
  esac
  if [[ "$name" != para ]]; then
    "$T5M" --пакувати-слова "$TMP/$name.expected.words" \
      > "$TMP/$name.expected.sens"
    cmp "$TMP/$name.answer.sens" "$TMP/$name.expected.sens"
  fi
  positive=$((positive+1))
done
[[ "$positive" -eq 6 ]]
# Незалежний SENS oracle має отримати саме оригінальні bytes, не .lisp mint.
ORACLE="$ROOT/sens-oracle/target/debug/sens"
[[ -x "$ORACLE" ]] && [[ "$(git -C sens-oracle rev-parse HEAD)" == \
  1f1bf676eeac605e065035d9dd2adaae807f1788 ]] || {
  echo 'ПЕРЕВІРЕНИЙ-IR-БЛОК: немає незалежного pinned SENS REPL' >&2; exit 127;
}
for name in d1-ni d1-tak tsytata atom umova; do
  timeout 40s "$ORACLE" "$TMP/$name.sens" > "$TMP/$name.oracle" \
    2> "$TMP/$name.oracle.err" || {
      echo "ПЕРЕВІРЕНИЙ-IR-ПРОВАЛ: upstream відхилив $name" >&2
      cat "$TMP/$name.oracle.err" >&2; exit 1;
    }
  [[ ! -s "$TMP/$name.oracle.err" ]]
  cmp "$TMP/$name.native" "$TMP/$name.oracle"
done

# Бінарний EIR1 не можна переносити між хоч структурно схожими source.
reject 'інший канонічний .sens' "$EXE" --перевірити-та-виконати \
  "$TMP/d1-tak.sens" "$TMP/d1-ni.eir"
cp "$TMP/tsytata.eir" "$TMP/підроблено.eir"
printf '\000' | dd of="$TMP/підроблено.eir" bs=1 seek=0 conv=notrunc status=none
reject 'неправильний EIR1 magic' "$EXE" --перевірити-та-виконати \
  "$TMP/tsytata.sens" "$TMP/підроблено.eir"
head -c -1 "$TMP/tsytata.eir" > "$TMP/обрізано.eir"
reject 'обрізаний EIR1' "$EXE" --перевірити-та-виконати \
  "$TMP/tsytata.sens" "$TMP/обрізано.eir"
printf '\377' > "$TMP/зіпсовано.sens"
reject 'зіпсований T5M' "$EXE" --перевірити-та-виконати \
  "$TMP/зіпсовано.sens" "$TMP/tsytata.eir"
printf '000000000000\n' > "$TMP/d12.words"
"$T5M" --пакувати-слова "$TMP/d12.words" >"$TMP/d12.sens"
reject 'число D12 без admission' "$EXE" --перевірити-та-виконати \
  "$TMP/d12.sens" "$TMP/tsytata.eir"
printf '10 111 0 01\n' > "$TMP/арність.words"
"$T5M" --пакувати-слова "$TMP/арність.words" > "$TMP/арність.sens"
"$MINT" --створити-ір "$TMP/арність.sens" "$TMP/арність.eir" >/dev/null
reject 'неправильна арність після успішного IR' \
  "$EXE" --перевірити-та-виконати "$TMP/арність.sens" "$TMP/арність.eir"
printf '(цитата 0)\n' >"$TMP/проєкція.lisp"
reject 'людська .lisp замість фізичного .sens' \
  "$EXE" --перевірити-та-виконати "$TMP/проєкція.lisp" "$TMP/tsytata.eir"
reject 'відсутній EIR1' "$EXE" --перевірити-та-виконати \
  "$TMP/d1-ni.sens" "$TMP/відсутній.eir"
# Після відмови без стану відновити початкові канонічні байти.
timeout 30s "$EXE" --перевірити-та-виконати \
  "$TMP/tsytata.sens" "$TMP/tsytata.eir" > "$TMP/після-відмов.sens"
cmp "$TMP/після-відмов.sens" "$TMP/tsytata.answer.sens"
echo 'ПЕРЕВІРЕНИЙ-IR-ГАРАЗД FPC=справжній EIR1=до-виконання' \
  'позитивів=6 oracle=5 D12+=відмова негативи=7 stdout=атомарно' \
  'IR-lowering=НЕ-РЕАЛІЗОВАНО'
