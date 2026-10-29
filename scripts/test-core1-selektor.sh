#!/usr/bin/env bash
# Core1.6: справжній FPC доказ ДРУГОГО й ТРЕТЬОГО pinned визначення Core1.
# Тіло замикання допускається лише як композиція ратифікованих селекторів;
# D3:011 «решта» виконує TBinaryExecutor, D4:1001 «друге» і D5:10011 «третє»
# виконує TCore4Runtime. Композиція CADR(CDR x) — лише незалежний оракул.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for cmd in fpc git timeout; do
  command -v "$cmd" >/dev/null || {
    echo "CORE1-SELEKTOR-БЛОК: немає $cmd" >&2; exit 127;
  }
done

./scripts/check-pin.sh
test -s external/sens/lib/core1.sens || {
  echo 'CORE1-SELEKTOR-БЛОК: немає pinned external/sens/lib/core1.sens' >&2; exit 1;
}
test -s external/sens/lib/core1.lisp || {
  echo 'CORE1-SELEKTOR-БЛОК: немає pinned external/sens/lib/core1.lisp' >&2; exit 1;
}
if git -C external/sens rev-parse HEAD >/dev/null 2>&1; then
  test "$(git -C external/sens rev-parse HEAD)" = "$PIN" || {
    echo 'CORE1-SELEKTOR-БЛОК: невірний pinned SHA external/sens' >&2; exit 1;
  }
fi

UNITS="$ROOT/build/m0.2/core1-selektor-units"
BIN="$ROOT/build/m0.2/core1-selektor-bin"
mkdir -p "$UNITS" "$BIN"

# Справжній FPC: -B повна перезбірка, -Cr/-Co/-Ci перевірки, -gh heaptrc.
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$UNITS" -FE"$BIN" -otest-core1-selektor \
  "$ROOT/scripts/test-core1-selektor.pas"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

timeout 120s "$BIN/test-core1-selektor" "$ROOT" "$TMP" \
  >"$TMP/fpc.stdout" 2>"$TMP/fpc.stderr"
grep -Fq 'CORE1-SELEKTOR-PASS checks=60' "$TMP/fpc.stdout" || {
  cat "$TMP/fpc.stdout" >&2; echo 'CORE1-SELEKTOR-БЛОК: не всі перевірки' >&2; exit 1;
}
grep -Fq 'CORE1-SELEKTOR-LIMIT=not-full-Core1' "$TMP/fpc.stdout" || {
  cat "$TMP/fpc.stdout" >&2; echo 'CORE1-SELEKTOR-БЛОК: немає межі доказу' >&2; exit 1;
}
grep -Fq '0 unfreed memory blocks' "$TMP/fpc.stderr" || {
  cat "$TMP/fpc.stderr" >&2; echo 'CORE1-SELEKTOR-БЛОК: витік памʼяті' >&2; exit 1;
}
cat "$TMP/fpc.stdout"

# Окремий CLI: той самий механізм, інший шлях входу (файл фізичного виклику).
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$UNITS" -FE"$BIN" -osenscore1selektor \
  "$ROOT/src/senscore1selektor.lpr" >/dev/null

timeout 60s "$BIN/senscore1selektor" --list "$ROOT" >"$TMP/list.out" 2>&1
grep -Eq '^CORE1-SELEKTOR-ADMITTED ([3-9]|[1-9][0-9]+)$' "$TMP/list.out" || {
  cat "$TMP/list.out" >&2; echo 'CORE1-SELEKTOR-БЛОК: перелік порожній' >&2; exit 1;
}
grep -Eq 'body=D5:10011\(arg0\)$' "$TMP/list.out" || {
  cat "$TMP/list.out" >&2; echo 'CORE1-SELEKTOR-БЛОК: немає D5:10011' >&2; exit 1;
}
grep -Eq 'body=D5:10011\(D3:011\(arg0\)\)$' "$TMP/list.out" || {
  cat "$TMP/list.out" >&2; echo 'CORE1-SELEKTOR-БЛОК: немає композиції' >&2; exit 1;
}

# Позитиви: друге, третє і третє-від-решти.
timeout 60s "$BIN/senscore1selektor" --run "$ROOT" "$TMP/call-0.sens" \
  >"$TMP/r0.out" 2>"$TMP/r0.err"
grep -Fq 'CORE1-SELEKTOR-RESULT 0000010' "$TMP/r0.out" || {
  cat "$TMP/r0.out" "$TMP/r0.err" >&2
  echo 'CORE1-SELEKTOR-БЛОК: друге з (a b c) не є b' >&2; exit 1;
}
timeout 60s "$BIN/senscore1selektor" --run "$ROOT" "$TMP/call-1.sens" \
  >"$TMP/r1.out" 2>"$TMP/r1.err"
grep -Fq 'CORE1-SELEKTOR-RESULT 0000100' "$TMP/r1.out" || {
  cat "$TMP/r1.out" "$TMP/r1.err" >&2
  echo 'CORE1-SELEKTOR-БЛОК: третє з (a b c) не є c' >&2; exit 1;
}
timeout 60s "$BIN/senscore1selektor" --run "$ROOT" "$TMP/call-2.sens" \
  >"$TMP/r2.out" 2>"$TMP/r2.err"
grep -Fq 'CORE1-SELEKTOR-RESULT 0001000' "$TMP/r2.out" || {
  cat "$TMP/r2.out" "$TMP/r2.err" >&2
  echo 'CORE1-SELEKTOR-БЛОК: третє від решти (a b c d) не є d' >&2; exit 1;
}

# Позитив із ДВОМА параметрами: створити-помилку → (маркер вид подробиці).
timeout 60s "$BIN/senscore1selektor" --run "$ROOT" "$TMP/call-3.sens" \
  >"$TMP/r3.out" 2>"$TMP/r3.err"
grep -Fq 'CORE1-SELEKTOR-RESULT 10 10 ' "$TMP/r3.out" || {
  cat "$TMP/r3.out" "$TMP/r3.err" >&2
  echo 'CORE1-SELEKTOR-БЛОК: немає вкладеного маркера у відповіді' >&2; exit 1;
}
grep -Fq '01 0000001 0000010 01' "$TMP/r3.out" || {
  cat "$TMP/r3.out" "$TMP/r3.err" >&2
  echo 'CORE1-SELEKTOR-БЛОК: аргументи не збережено у відповіді' >&2; exit 1;
}

# Негативи: код 2, порожній stdout, діагностика в stderr.
for bad in call-short.sens call-alien.sens call-bad.sens call-3-short.sens; do
  set +e
  timeout 60s "$BIN/senscore1selektor" --run "$ROOT" "$TMP/$bad" \
    >"$TMP/neg.out" 2>"$TMP/neg.err"
  code=$?
  set -e
  test "$code" -eq 2 || {
    echo "CORE1-SELEKTOR-БЛОК: $bad дав код $code, очікувався 2" >&2; exit 1;
  }
  test ! -s "$TMP/neg.out" || {
    cat "$TMP/neg.out" >&2
    echo "CORE1-SELEKTOR-БЛОК: $bad лишив частковий stdout" >&2; exit 1;
  }
  grep -Fq 'CORE1-SELEKTOR-REFUSED' "$TMP/neg.err" || {
    cat "$TMP/neg.err" >&2
    echo "CORE1-SELEKTOR-БЛОК: $bad без діагностики" >&2; exit 1;
  }
done

echo 'CORE1-SELEKTOR-ГАРАЗД pinned=Contract12 D4:1001=native D5:10011=native oracle=CADR(CDR)'
