#!/usr/bin/env bash
# G6.264 — чинний компілятор фізичного ADD→NEG через спільний host NEG32.
# Вхід: уже ратифіковані D12/D24 .sens зі scripts/test-elfd12addneg.sh.
# Вихід: фактично виконані ELF64/T5M, 14 позитивів, 11 негативів.
# Файли, потоки і код належать дочірньому тесту/тимчасовому каталогу.
# 1) Чому host NEG32 не створює нового числового закону?
# 2) Чому проміжний D24 не можна звузити до D12?
# 3) Навіщо перевірка ELF opcode і справжнього T5M stdout?
# 4) Чому відсутній SENS_ORACLE_BIN слід називати NOT-RUN?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v timeout >/dev/null || {
  echo 'D12-ADDNEG-БЛОК: відсутній timeout' >&2; exit 127;
}
command -v mktemp >/dev/null || {
  echo 'D12-ADDNEG-БЛОК: відсутній mktemp' >&2; exit 127;
}
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
if ! timeout 360s bash "$ROOT/scripts/test-elfd12addneg.sh" >"$LOG" 2>&1; then
  tail -n 60 "$LOG" >&2
  echo 'D12-ADDNEG-ПРОВАЛ: checked FPC / фізичні ELF64 / негативи' >&2
  exit 1
fi
mapfile -t ROWS < <(grep '^D12-ДВІ-ДІЇ-ГАРАЗД ' "$LOG")
if (( ${#ROWS[@]} != 1 )); then
  tail -n 40 "$LOG" >&2
  echo 'D12-ADDNEG-ПРОВАЛ: не один реальний машинний підсумок' >&2
  exit 1
fi
if [[ "${ROWS[0]}" =~ ^D12-ДВІ-ДІЇ-ГАРАЗД[[:space:]]форм=14[[:space:]]проміжних-D24=4[[:space:]]фінальних-D24=6[[:space:]]pinned-oracle=(0|14)[[:space:]]негативів=11[[:space:]]ELF=ADD,NEG[[:space:]]T5M=точно[[:space:]]RAPL=НЕ_ВИМІРЯНО$ ]]; then
  ORACLE="${BASH_REMATCH[1]}"
else
  tail -n 40 "$LOG" >&2
  echo 'D12-ADDNEG-ПРОВАЛ: неповна матриця фізичних машинних доказів' >&2
  exit 1
fi
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  [[ "$ORACLE" == 14 ]] || {
    echo 'D12-ADDNEG-ПРОВАЛ: заявлений oracle не виконаний' >&2
    exit 1
  }
  ORACLE_STATE='14/14'
else
  [[ "$ORACLE" == 0 ]] || {
    echo 'D12-ADDNEG-ПРОВАЛ: необґрунтований oracle без binary' >&2
    exit 1
  }
  ORACLE_STATE='NOT-RUN'
fi
printf '%s\n' "${ROWS[0]}"
printf 'VERIFIED-D12ADDNEG-PASS FPC=checked ELF64=14 intermediate-D24=4 result-D24=6 negatives=11 T5M=byte-exact oracle=%s energy=NOT-MEASURED\n' "$ORACLE_STATE"
