#!/usr/bin/env bash
# G6.207 — вимірювання дозволено лише після механічного допуску
# параметрів і реального виконання SENS-lowered ELF64.
# Це НЕ доказ мовного паритету з незалежним SENS REPL і НЕ джоулі.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SCRIPT="$ROOT/scripts/run-fib-twins.sh"

bash -n "$SCRIPT"
FAILS=0
negative() {
  local label="$1"
  shift
  if "$@" > "$TMP/$label.out" 2>&1; then
    echo "FIB-MEASURE-ЗБІЙ: негатив $label помилково прийнято" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
  grep -Fq 'FIB-TWINS-БЛОК:' "$TMP/$label.out" || {
    echo "FIB-MEASURE-ЗБІЙ: немає ранньої діагностики $label" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  }
  FAILS=$((FAILS+1))
}

# Усі негативи відхиляються ДО першого FPC/GCC/Rust запуску.
negative nevіdomyi bash "$SCRIPT" --невідомий-прапорець
negative dva-koreni bash "$SCRIPT" "$ROOT" "$ROOT" --measure
negative ne-korin bash "$SCRIPT" /dev/null --measure
negative n-minus env FIB_NS=-1 bash "$SCRIPT" --measure
negative n-velyke env FIB_NS=36 bash "$SCRIPT" --measure
negative n-zirkа env 'FIB_NS=*' bash "$SCRIPT" --measure
negative n-porozhnie env FIB_NS= bash "$SCRIPT" --measure
negative kilkist-0 env FIB_REPEATS=0 bash "$SCRIPT" --measure
negative kilkist-21 env FIB_REPEATS=21 bash "$SCRIPT" --measure
negative kilkist-porozhnia env FIB_REPEATS= bash "$SCRIPT" --measure

# Один справжній нативний мікрозріз: pinned SENS body → x86-64 ELF;
# C/FPC/Rust використовуються лише якщо інструменти встановлені.
command -v fpc >/dev/null || {
  echo 'FIB-MEASURE-БЛОК: потрібен реальний FPC' >&2
  exit 127
}
env FIB_NS=10 FIB_REPEATS=1 bash "$SCRIPT" --measure \
  > "$TMP/measure.out" 2> "$TMP/measure.err" || {
    echo 'FIB-MEASURE-ЗБІЙ: реальний FPC/SENS-lowered прогін' >&2
    tail -n 60 "$TMP/measure.out" >&2
    tail -n 60 "$TMP/measure.err" >&2
    exit 1
  }
grep -Fq 'n=10 оракул=55 звірено' "$TMP/measure.out"
grep -Fq 'n=10 fib-pas сер.=' "$TMP/measure.out"
grep -Fq 'n=10 fib-sens сер.=' "$TMP/measure.out"
grep -Fxq 'FIB-TWINS-PASS' "$TMP/measure.out"
grep -Fq 'не енергія' "$TMP/measure.out"
echo "FIB-MEASURE-GATE-PASS negatives=$FAILS native=yes n=10 oracle=55 energy=NOT-MEASURED"
