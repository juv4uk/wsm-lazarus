#!/usr/bin/env bash
# G6.247 — перевірений звіт host x86-64 ALU без ручного лічильника ELF.
# Дочірній FPC-тест реально запускає ELF64 та звіряє фізичні T5M байти.
# Не вводить нових законів SENS, не трактує D7 чи числові домени D12+.
# Вхід: stdout одного завершеного дочірнього тесту (Bash рядок).
# Вихід: один підтверджений підсумок; додаткових файлових ресурсів немає.
# Питання: 1) Чому число ELF визначає тест, а не текстова константа?
# 2) Чому повторний підсумок неоднозначний?
# 3) Чому ELF64 і T5M мають однакову кількість результатів?
# 4) Чому код помилки дочірньої FPC перевірки не можна приховувати?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v timeout >/dev/null || { echo 'X64-ALU-БЛОК: немає timeout' >&2; exit 127; }

REPORT="$(timeout 180s bash "$ROOT/scripts/test-x64alu.sh")"
printf '%s\n' "$REPORT"
mapfile -t ROWS < <(printf '%s\n' "$REPORT" | grep '^X64-ALU-МАШИНА-ГАРАЗД ')
if (( ${#ROWS[@]} != 1 )); then
  echo 'X64-ALU-ЗВІТ-ПОМИЛКА: потрібен рівно один машинний підсумок' >&2
  exit 1
fi
if [[ "${ROWS[0]}" =~ ^X64-ALU-МАШИНА-ГАРАЗД[[:space:]]golden=([1-9][0-9]*)[[:space:]]negative=([1-9][0-9]*)[[:space:]]elf64=([1-9][0-9]*)[[:space:]]t5m=([1-9][0-9]*)[[:space:]]energy=NOT-MEASURED$ ]]; then
  GOLDEN="${BASH_REMATCH[1]}"
  NEGATIVE="${BASH_REMATCH[2]}"
  ELF="${BASH_REMATCH[3]}"
  T5M="${BASH_REMATCH[4]}"
else
  echo 'X64-ALU-ЗВІТ-ПОМИЛКА: некоректні лічильники або одиниці' >&2
  exit 1
fi
if [[ "$ELF" != "$T5M" ]]; then
  echo 'X64-ALU-ЗВІТ-ПОМИЛКА: ELF64 і T5M не збігаються' >&2
  exit 1
fi
printf 'VERIFIED-X64-ALU-PASS FPC=checked golden=%s negative=%s ELF64=%s T5M=byte-exact energy=NOT-MEASURED\n' \
  "$GOLDEN" "$NEGATIVE" "$ELF"
