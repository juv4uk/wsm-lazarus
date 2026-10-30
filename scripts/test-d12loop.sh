#!/usr/bin/env bash
# G6.73: справжній FPC + справжній запуск нативного ЦИКЛУ навантаження.
# Очікувані коди виходу рахує незалежний оракул (ланцюжок AddNumericPhysical),
# а не мій емітер; тут лише порівняння реального коду виходу ELF із ним.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

for cmd in fpc timeout; do
  command -v "$cmd" >/dev/null || {
    echo "SENS-D12LOOP-БЛОК: немає $cmd" >&2; exit 127;
  }
done

UNITS="$ROOT/build/m0.2/d12loop-units"
BIN="$ROOT/build/m0.2/d12loop-bin"
mkdir -p "$UNITS" "$BIN"

# -gh свідомо НЕ вжито: у цій збірці FPC heaptrc не підключається
# детерміновано, а ставити гейт, який локально не можна ні підтвердити,
# ні опровергнути, — це фальшивий сигнал. Предмет доказу тут — машинний
# цикл і збіг із оракулом, а не стан купи.
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$UNITS" -FE"$BIN" -otest-d12loop "$ROOT/scripts/test-d12loop.pas"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

timeout 120s "$BIN/test-d12loop" "$ROOT" "$TMP" >"$TMP/fpc.stdout" 2>"$TMP/fpc.stderr"
grep -Fq 'SENS-D12LOOP-PASS checks=41' "$TMP/fpc.stdout" || {
  cat "$TMP/fpc.stdout" "$TMP/fpc.stderr" >&2
  echo 'SENS-D12LOOP-БЛОК: не всі перевірки' >&2; exit 1;
}
cat "$TMP/fpc.stdout"

# Реальний запуск згенерованих ELF: код виходу мусить дорівнювати оракулу.
chmod +x "$TMP"/*.elf
# G6.227: дизасемблюємо реальні коди двох native ELF — до запуску.
command -v objdump >/dev/null || {
  echo 'SENS-D12LOOP-БЛОК: немає objdump' >&2; exit 127
}
for label in loop-7 sum-10; do
  tail -c +121 "$TMP/$label.elf" >"$TMP/$label.code"
  timeout 10s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.code" >"$TMP/$label.disasm"
  grep -Eiq 'movzx[[:space:]]+edi,al' "$TMP/$label.disasm" || {
    echo "SENS-D12LOOP-БЛОК: у $label не знайдено MOVZX" >&2; exit 1
  }
  if grep -Eiq 'and[[:space:]]+edi,0xffffffff' "$TMP/$label.disasm"; then
    echo "SENS-D12LOOP-БЛОК: у $label лишився no-op AND EDI,-1" >&2; exit 1
  fi
done
echo 'SENS-D12LOOP-ISA-PASS samples=2 machine=MOVZX-EDI-AL old-AND-imm8=refused'
while read -r tag count expected; do
  test "$tag" = 'EXPECT' || continue
  case "$count" in
    sum-*) file="$TMP/$count.elf" ;;
    -1)    file="$TMP/loop-minus1.elf" ;;
    *)     file="$TMP/loop-$count.elf" ;;
  esac
  set +e
  timeout 60s "$file"
  code=$?
  set -e
  test "$code" -eq "$expected" || {
    echo "SENS-D12LOOP-БЛОК: N=$count дав код $code, оракул каже $expected" >&2
    exit 1;
  }
  echo "SENS-D12LOOP-RUN N=$count exit=$code ok"
done <"$TMP/fpc.stdout"

# Окремий CLI: той самий механізм через файловий вхід і атомарну публікацію.
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$UNITS" -FE"$BIN" -osensd12loop "$ROOT/src/sensd12loop.lpr"

timeout 60s "$BIN/sensd12loop" --build "$TMP/k5.sens" 7 "$TMP/cli-7.elf" \
  >"$TMP/cli.out" 2>"$TMP/cli.err"
grep -Fq 'SENS-D12LOOP-BUILT bytes=151 iterations=7' "$TMP/cli.out" || {
  cat "$TMP/cli.out" "$TMP/cli.err" >&2
  echo 'SENS-D12LOOP-БЛОК: CLI не збудував ELF' >&2; exit 1;
}
test -x "$TMP/cli-7.elf" || {
  echo 'SENS-D12LOOP-БЛОК: CLI не зробив файл виконуваним' >&2; exit 1;
}
set +e
timeout 60s "$TMP/cli-7.elf"
cli_code=$?
set -e
test "$cli_code" -eq 35 || {
  echo "SENS-D12LOOP-БЛОК: CLI-ELF дав код $cli_code, очікувався 35" >&2; exit 1;
}
echo "SENS-D12LOOP-RUN cli exit=$cli_code ok"

# Негативи CLI: код 2, порожній stdout, діагностика в stderr.
printf 'X' >"$TMP/not-a-sens.sens"
for args in "$TMP/not-a-sens.sens 1 $TMP/n1.elf" \
            "$TMP/k5.sens 0 $TMP/n2.elf" \
            "$TMP/k5.sens 1000000001 $TMP/n3.elf" \
            "$TMP/missing.sens 1 $TMP/n4.elf"; do
  set +e
  # shellcheck disable=SC2086
  timeout 60s "$BIN/sensd12loop" --build $args >"$TMP/neg.out" 2>"$TMP/neg.err"
  code=$?
  set -e
  test "$code" -eq 2 || {
    echo "SENS-D12LOOP-БЛОК: негатив '$args' дав код $code, очікувався 2" >&2; exit 1;
  }
  test ! -s "$TMP/neg.out" || {
    cat "$TMP/neg.out" >&2
    echo "SENS-D12LOOP-БЛОК: негатив '$args' лишив частковий stdout" >&2; exit 1;
  }
  grep -Fq 'SENS-D12LOOP-REFUSED' "$TMP/neg.err" || {
    cat "$TMP/neg.err" >&2
    echo "SENS-D12LOOP-БЛОК: негатив '$args' без діагностики" >&2; exit 1;
  }
done

# Workload `loop` (сума 0..N) через CLI: N приходить із .sens D24.
timeout 60s "$BIN/sensd12loop" --sum "$TMP/sum-10.sens" "$TMP/cli-sum-10.elf" \
  >"$TMP/clisum.out" 2>"$TMP/clisum.err"
grep -Fq 'SENS-D12LOOP-SUM-BUILT bytes=148' "$TMP/clisum.out" || {
  cat "$TMP/clisum.out" "$TMP/clisum.err" >&2
  echo 'SENS-D12LOOP-БЛОК: CLI не збудував sum-ELF' >&2; exit 1;
}
set +e
timeout 60s "$TMP/cli-sum-10.elf"
sum_code=$?
set -e
test "$sum_code" -eq 55 || {
  echo "SENS-D12LOOP-БЛОК: CLI sum-10 дав код $sum_code, очікувався 55" >&2; exit 1;
}
echo "SENS-D12LOOP-RUN cli sum-10 exit=$sum_code ok"

echo 'SENS-D12LOOP-ГАРАЗД pinned=D12 loop=native oracle=AddNumericPhysical'
