#!/usr/bin/env bash
# G6.252 — входження наявного host LEA ISA/ELF64 свідка до FPC verified gate.
# Вхід: завершений stdout scripts/test-x64lea.sh; не SENS-форма і не D7-проєкція.
# Вихід: один чесний звіт про фактично виконані 5376 GNU-as порівнянь і 2 ELF64.
# Жодних додаткових об'єктів або постійних файлів: лише bash-рядок у процесі.
# Запитання: 1) Чому LEA — host інструкція, не мовний закон?
# 2) Чому результат дочірнього тесту важливіший за статичну цифру wrapper-а?
# 3) Як невдача FPC або фізичного cmp доходить до загального CI?
# 4) Чому негативи треба зберігати навіть для успішних ELF?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v timeout >/dev/null || {
  echo 'X64-LEA-БЛОК: відсутній timeout' >&2
  exit 127
}

REPORT="$(timeout 360s bash "$ROOT/scripts/test-x64lea.sh")"
printf '%s\n' "$REPORT"
mapfile -t ROWS < <(printf '%s\n' "$REPORT" | grep '^X64-LEA-МАШИНА-ГАРАЗД ')
if (( ${#ROWS[@]} != 1 )); then
  echo 'X64-LEA-ЗВІТ-ПОМИЛКА: потрібен рівно один машинний підсумок' >&2
  exit 1
fi
if [[ "${ROWS[0]}" =~ ^X64-LEA-МАШИНА-ГАРАЗД[[:space:]]vectors=([1-9][0-9]*)[[:space:]]golden=([1-9][0-9]*)[[:space:]]negative=([1-9][0-9]*)[[:space:]]elf64=([1-9][0-9]*)[[:space:]]energy=NOT-MEASURED$ ]]; then
  VECTORS="${BASH_REMATCH[1]}"
  GOLDEN="${BASH_REMATCH[2]}"
  NEGATIVE="${BASH_REMATCH[3]}"
  ELF="${BASH_REMATCH[4]}"
else
  echo 'X64-LEA-ЗВІТ-ПОМИЛКА: некоректний машинний підсумок' >&2
  exit 1
fi
printf 'VERIFIED-X64-LEA-PASS FPC=checked GNU-as=%s golden=%s negative=%s ELF64=%s T5M=byte-exact energy=NOT-MEASURED\n' \
  "$VECTORS" "$GOLDEN" "$NEGATIVE" "$ELF"
