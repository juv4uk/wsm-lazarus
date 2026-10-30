#!/usr/bin/env bash
# G6.158 — незалежні FPC -O1/-O2 збірки одного фізичного T5M→WideIR→ELF.
# Перевіряємо реальні native ELF, а не лише SHA тексту чи структурний IR.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout mktemp cmp grep readelf chmod python3; do
  command -v "$tool" >/dev/null || { echo "ПОТІК-ВІДТВОРЕННЯ-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ПОТІК-ВІДТВОРЕННЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'ПОТІК-ВІДТВОРЕННЯ-БЛОК: незалежний SENS REPL обовʼязковий' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if (( rc )); then
    echo "ПОТІК-ВІДТВОРЕННЯ-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/o1/units" "$TMP/o1/bin" "$TMP/o2/units" "$TMP/o2/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for profile in o1 o2; do
  if [[ "$profile" == o1 ]]; then OPT=-O1; else OPT=-O2; fi
  # Окремі -FU і -FE не дозволяють другій збірці перевикористати
  # compiled Pascal units першої. Всі байти результату належать CLI.
  for spec in 'src/senswidepotikelf.lpr senswidepotikelf' 'scripts/test-irwidefront.pas test-irwidefront'; do
    read -r src name <<< "$spec"
    timeout 180s "$FPC_BIN" -B "$OPT" -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/$profile/units" -FE"$TMP/$profile/bin" "-o$name" \
      "$ROOT/$src" >"$TMP/$profile-$name.build" 2>&1 || {
        cat "$TMP/$profile-$name.build" >&2; exit 1;
      }
    test -x "$TMP/$profile/bin/$name"
  done
done
timeout 40s "$TMP/o1/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
heap_ok() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1" || {
      cat "$1" >&2; return 1;
    }
  fi
}
heap_ok "$TMP/fixtures.err"
MODE=--скомпілювати-фізичний-потік
COUNT=0
ORACLE_COUNT=0
while IFS=$'\t' read -r label kind a b expected width; do
  test -n "$label"
  physical="$TMP/physical/$label.sens"
  first="$TMP/$label-o1.elf"
  second="$TMP/$label-o2.elf"
  # Зміна host TZ/locale/umask не має потрапляти в машинні байти.
  (umask 077; LC_ALL=C TZ=UTC timeout 25s \
    "$TMP/o1/bin/senswidepotikelf" "$MODE" <"$physical" >"$first" \
    2>"$TMP/$label-o1.err")
  (umask 027; LC_ALL=C.UTF-8 TZ=Pacific/Kiritimati timeout 25s \
    "$TMP/o2/bin/senswidepotikelf" "$MODE" <"$physical" >"$second" \
    2>"$TMP/$label-o2.err")
  heap_ok "$TMP/$label-o1.err"
  heap_ok "$TMP/$label-o2.err"
  cmp "$first" "$second"
  readelf -h "$first" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  ! readelf -l "$first" | grep -Eq 'INTERP|DYNAMIC'
  for profile in o1 o2; do
    elf="$TMP/$label-$profile.elf"
    chmod 700 "$elf"
    timeout 5s "$elf" >"$TMP/$label-$profile.actual.sens" \
      2>"$TMP/$label-$profile.machine.err"
    test ! -s "$TMP/$label-$profile.machine.err"
    cmp "$TMP/physical/$label.expected.sens" "$TMP/$label-$profile.actual.sens"
  done
  if [[ -n "$ORACLE" ]]; then
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/$label.oracle.lisp" ;;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/$label.oracle.lisp" ;;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/$label.oracle.lisp" ;;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/$label.oracle.lisp" ;;
      *) echo 'невідомий host kind fixture' >&2; exit 71 ;;
    esac
    timeout 60s "$ORACLE" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle.out"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  COUNT=$((COUNT+1))
done <"$TMP/physical/cases.tsv"
test "$COUNT" -eq 16
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 16; fi

# Негативи мають завершитися 2/порожній stdout незалежно від -O1/-O2.
printf '(нуль? 0)\n' >"$TMP/text-ukr.lisp"
NEG=0
for profile in o1 o2; do
  for bad in "$TMP/physical/bad-t5m.sens" "$TMP/physical/bad-less-d24.sens" \
             "$TMP/physical/two-roots.sens" "$TMP/physical/empty.sens" \
             "$TMP/text-ukr.lisp"; do
    rc=0
    timeout 25s "$TMP/$profile/bin/senswidepotikelf" "$MODE" \
      <"$bad" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
    test "$rc" -eq 2
    test ! -s "$TMP/reject.out"
    grep -Fq 'ШИРОКИЙ-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
    heap_ok "$TMP/reject.err"
    NEG=$((NEG+1))
  done
  # Після серії відмов знову побайтово відтворити позитивний ELF.
  timeout 25s "$TMP/$profile/bin/senswidepotikelf" "$MODE" \
    <"$TMP/physical/09.sens" >"$TMP/$profile.recovered.elf" \
    2>"$TMP/$profile.recovered.err"
  heap_ok "$TMP/$profile.recovered.err"
  cmp "$TMP/09-o1.elf" "$TMP/$profile.recovered.elf"
done
test "$NEG" -eq 10
echo "ПОТІК-ВІДТВОРЕННЯ-ГАРАЗД physical=$COUNT identical=$COUNT native=$((2*COUNT)) oracle=$ORACLE_COUNT negative=$NEG fpc=O1+O2 env=2 recovery=2 energy=НЕ-ВИМІРЯНО"
