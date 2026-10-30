#!/usr/bin/env bash
# G6.94 — близнюки навантаження `fib`: збірка, ЗВІРКА КОДІВ ВИХОДУ
# з незалежним оракулом, і — лише за --measure — вимірювання часу.
#
# Без --measure скрипт нічого не міряє: він доводить, що всі близнюки
# рахують те саме. Числа публікуються лише разом із походженням.
set -euo pipefail
# Режим і корінь — незалежні: --measure першим аргументом НЕ є шляхом.
# Шляхи/числові параметри перевіряються до першого FPC/Rust/GCC запуску.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_SET=0
MEASURE=0
REPEATS="${FIB_REPEATS:-5}"
NS="${FIB_NS:-10 20 25 30 35}"

for arg in "$@"; do
  case "$arg" in
    --measure) MEASURE=1 ;;
    --*) printf 'FIB-TWINS-БЛОК: невідомий прапорець %s\n' "$arg" >&2; exit 2 ;;
    *)
      if ((ROOT_SET)); then
        echo 'FIB-TWINS-БЛОК: можна вказати лише один корінь' >&2
        exit 2
      fi
      ROOT="$arg"
      ROOT_SET=1
      ;;
  esac
done
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || {
  echo 'FIB-TWINS-БЛОК: корінь не існує' >&2; exit 2;
}
if [[ ! -f "$ROOT/src/sensfiblower.lpr" ]]; then
  echo 'FIB-TWINS-БЛОК: це не корінь компілятора SENS' >&2; exit 2
fi
if [[ ! "$REPEATS" =~ ^[1-9][0-9]?$ ]] || (( REPEATS > 20 )); then
  echo 'FIB-TWINS-БЛОК: FIB_REPEATS має бути 1..20' >&2; exit 2
fi
# Заборонити glob expansion параметра N. Підміна вхідного діапазону
# не повинна спричинити нескінченну рекурсію або хибний оракул.
set -f
if [[ -z "${NS//[[:space:]]/}" ]]; then
  echo 'FIB-TWINS-БЛОК: порожній список FIB_NS' >&2; exit 2
fi
NCOUNT=0
for N in $NS; do
  if [[ ! "$N" =~ ^(0|[1-9][0-9]?)$ ]] || (( N > 35 )); then
    echo "FIB-TWINS-БЛОК: N=$N поза точним host-діапазоном 0..35" >&2
    exit 2
  fi
  NCOUNT=$((NCOUNT + 1))
  if (( NCOUNT > 16 )); then
    echo 'FIB-TWINS-БЛОК: понад 16 входів у вимірюванні' >&2; exit 2
  fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0

oracle() {
  local n="$1" a=0 b=1 t i
  for ((i=0; i<n; i++)); do t=$((a+b)); a=$b; b=$t; done
  echo $((a & 255))
}

have() { command -v "$1" >/dev/null 2>&1; }

say() { printf 'FIB-TWINS %s\n' "$*"; }
bad() { printf 'FIB-TWINS-ЗБІЙ %s\n' "$*"; FAIL=1; }

# Нативний SENS-шлях: ELF із точного D24 .sens.
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -otest-elffib "$ROOT/scripts/test-elffib.pas" > "$WORK/build-elffib.log" 2>&1 \
  || { bad "збірка емітера SENS-ELF"; exit 1; }
"$WORK/b/test-elffib" > "$WORK/elffib.log" 2>&1 \
  || { bad "самотест SENS-ELF"; cat "$WORK/elffib.log"; exit 1; }
say "SENS-ELF: самотест PASS"

# Тіло SENS, знижене в машинний код (не host-код навантаження).
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -osensfiblower "$ROOT/src/sensfiblower.lpr" > "$WORK/build-lower.log" 2>&1 \
  || { bad "збірка sensfiblower"; cat "$WORK/build-lower.log"; exit 1; }
say "SENS-lowered: емітер зібрано"

for N in $NS; do
  WANT="$(oracle "$N")"

  # C
  if have gcc; then
    gcc -O2 -DN="$N" -o "$WORK/fib-c" "$ROOT/benchmarks/cross-language/fib/fib.c"
    set +e; "$WORK/fib-c"; GOT=$?; set -e
    [ "$GOT" = "$WANT" ] || bad "C fib($N)=$GOT, оракул $WANT"
  fi

  # Rust: include! шукає файл ПОРУЧ із джерелом, тому копіюємо fib.rs
  # у робочу теку й генеруємо fib_n.rs там само.
  if have rustc; then
    cp "$ROOT/benchmarks/cross-language/fib/fib.rs" "$WORK/fib.rs"
    printf 'const N: u64 = %s;\n' "$N" > "$WORK/fib_n.rs"
    if rustc -O --edition 2021 -o "$WORK/fib-rs" "$WORK/fib.rs" \
         > "$WORK/build-rs.log" 2>&1; then
      set +e; "$WORK/fib-rs"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "Rust fib($N)=$GOT, оракул $WANT"
    else
      bad "збірка Rust-близнюка"
      tail -3 "$WORK/build-rs.log"
    fi
  fi

  # Free Pascal: N вшивається через згенерований include
  if have fpc; then
    printf 'const FIB_N = %s;\n' "$N" > "$WORK/fib_n.inc"
    if fpc -B -O2 -Fi"$WORK" -FU"$WORK/u" -FE"$WORK/b" \
         -o"$WORK/fib-pas" "$ROOT/benchmarks/cross-language/fib/fib.pas" \
         > "$WORK/build-pas.log" 2>&1; then
      set +e; "$WORK/fib-pas"; GOT=$?; set -e
      [ "$GOT" = "$WANT" ] || bad "FPC fib($N)=$GOT, оракул $WANT"
    else
      bad "збірка FPC-близнюка"
      tail -3 "$WORK/build-pas.log"
    fi
  fi

  # Тіло SENS, знижене в x86-64
  "$WORK/b/sensfiblower" "$ROOT" "$N" "$WORK/fib-sens" \
    || { bad "зниження тіла SENS для n=$N"; exit 1; }
  chmod +x "$WORK/fib-sens"
  set +e; "$WORK/fib-sens"; GOT=$?; set -e
  [ "$GOT" = "$WANT" ] || bad "SENS-lowered fib($N)=$GOT, оракул $WANT"

  say "n=$N оракул=$WANT звірено"
done

if [ "$FAIL" -ne 0 ]; then
  echo "FIB-TWINS-FAIL"
  exit 1
fi

if [ "$MEASURE" -eq 1 ]; then
  say "вимірювання: $REPEATS повторів на кожне n (час процесу, не енергія)"
  say "походження: SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo невідомо)"
  say "CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || echo невідомо)"
  have fpc && say "FPC=$(fpc -iV)"
  have gcc && say "GCC=$(gcc -dumpversion)"
  have rustc && say "RUSTC=$(rustc --version | cut -d' ' -f2)"

  # Стіновий час процесу у мкс, НЕ енергія та НЕ pure fib compute-time.
  # Кожен виміряний виконуваний файл знову перевіряємо через host oracle:
  # навіть після успішної початкової звірки жоден код помилки не є зразком.
  # 1) Чому код виходу fib може бути ненульовим?
  # 2) Чому перевірка лише перед бенчмарком не захищає кожен повтор?
  # 3) Чому повертаємо лише числовий wall-clock, а не джоулі?
  # 4) Хто володіє тимчасовими виконуваними файлами?
  measure_one() {
    local bin="$1" want="$2" start end got
    start=$(date +%s%N) || return 1
    set +e
    "$bin"
    got=$?
    set -e
    end=$(date +%s%N) || return 1
    if [[ "$got" != "$want" ]]; then
      printf 'FIB-TWINS-ЗБІЙ: measured %s повернув %s, оракул=%s\n' \
        "$bin" "$got" "$want" >&2
      return 1
    fi
    if [[ ! "$start" =~ ^[0-9]+$ || ! "$end" =~ ^[0-9]+$ ]] || (( end < start )); then
      echo 'FIB-TWINS-ЗБІЙ: часовий лічильник недостовірний' >&2
      return 1
    fi
    echo $(( (end - start) / 1000 ))
  }

  for N in $NS; do
    WANT="$(oracle "$N")"
    # Самотест host SENS-ELF уже підтверджено вище; у вимірюванні
    # порівнюємо саме SENS-lowered ELF, не виконуємо зайвого host fib.
    printf 'const FIB_N = %s;\n' "$N" > "$WORK/fib_n.inc"
    fpc -B -O2 -Fi"$WORK" -FU"$WORK/u" -FE"$WORK/b" \
      -o"$WORK/fib-pas" "$ROOT/benchmarks/cross-language/fib/fib.pas" \
      > "$WORK/measure-pas.log" 2>&1 || {
        bad "збірка FPC-близнюка у вимірюванні n=$N"
        tail -n 20 "$WORK/measure-pas.log" >&2
        exit 1
      }
    if have gcc; then
      gcc -O2 -DN="$N" -o "$WORK/fib-c" "$ROOT/benchmarks/cross-language/fib/fib.c" \
        || { bad "збірка C-близнюка у вимірюванні n=$N"; exit 1; }
    fi
    if have rustc; then
      printf 'const N: u64 = %s;\n' "$N" > "$WORK/fib_n.rs"
      # include! шукає файл поряд із .rs; використовуємо вже перевірену
      # робочу копію, а не шлях оригіналу з відсутнім fib_n.rs.
      rustc -O --edition 2021 -o "$WORK/fib-rs" \
        "$WORK/fib.rs" > "$WORK/measure-rs.log" 2>&1 || {
          bad "збірка Rust-близнюка у вимірюванні n=$N"
          tail -n 20 "$WORK/measure-rs.log" >&2
          exit 1
        }
    fi

    # Не дозволяти старому ELF іншого N замінити невдалий новий lowering.
    rm -f "$WORK/fib-sens"
    "$WORK/b/sensfiblower" "$ROOT" "$N" "$WORK/fib-sens" \
      > "$WORK/measure-sens.log" 2>&1 || {
        bad "native SENS lowering у вимірюванні n=$N"
        tail -n 20 "$WORK/measure-sens.log" >&2
        exit 1
      }
    [[ -s "$WORK/fib-sens" ]] || {
      bad "порожній SENS-lowered ELF n=$N"; exit 1
    }
    chmod +x "$WORK/fib-sens" || {
      bad "неможливо виконати SENS-lowered ELF n=$N"; exit 1
    }
    for twin in fib-c fib-rs fib-pas fib-sens; do
      # Відсутній інструмент — окремий факт, але коли інструмент
      # встановлено, відсутній чи неправильний ELF — завжди FAIL.
      if [[ "$twin" == fib-rs ]] && ! have rustc; then continue; fi
      if [[ "$twin" == fib-c ]] && ! have gcc; then continue; fi
      [[ -x "$WORK/$twin" ]] || {
        bad "немає зібраного $twin для n=$N"; exit 1
      }
      total=0
      for ((r=0; r<REPEATS; r++)); do
        sample=$(measure_one "$WORK/$twin" "$WANT") || {
          bad "недостовірний повтор n=$N $twin r=$r"; exit 1
        }
        total=$((total + sample))
      done
      say "n=$N $twin сер.=$(( total / REPEATS )) мкс"
    done
  done
  say "УВАГА: числа — час процесу, не енергія. Енергія потребує окремого протоколу."
else
  say "вимірювання не запускалося (додайте --measure)"
fi

echo "FIB-TWINS-PASS"
