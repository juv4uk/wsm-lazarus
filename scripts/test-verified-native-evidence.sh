#!/usr/bin/env bash
# G6.233 — наявний PR/FPC gate запускає незалежні ELF64 host-негативи.
# Тільки машинна атестація: це НЕ оракул законів SENS і НЕ вимір енергії.
# Тип: один bash-процес + дочірній Python unittest, без Pascal runtime-об'єктів.
# Вхід: наявний набір тестів і його тимчасові фізичні .sens/.elf свідки.
# Allocation/lifetime: журнал mktemp належить цьому процесу, trap прибирає його.
# Результат: exit 0 + підтвердження 17+ реальних тестів або fail-closed exit != 0.
#
# 1. Чому точний машинний stdout не є мовним SENS oracle?
# 2. Чому забороняємо пропущені Linux x86-64 тести?
# 3. Чому не створюємо новий FPC workflow для вже наявної перевірки?
# 4. Що відбувається з тимчасовим журналом після відмови?
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in python3 timeout mktemp grep sed tail uname; do
  command -v "$tool" >/dev/null || {
    echo "НАТИВНИЙ-ELF-ГЕЙТ-БЛОК: немає $tool" >&2
    exit 127
  }
done
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "НАТИВНИЙ-ELF-ГЕЙТ-БЛОК: потрібен Linux x86-64" >&2
  exit 127
fi
LOG="$(mktemp)"
cleanup() {
  local code=$?
  if (( code != 0 )); then
    echo "НАТИВНИЙ-ELF-ГЕЙТ-ПРОВАЛ: exit=$code" >&2
    tail -n 24 "$LOG" >&2 || true
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

# Не витрачаємо новий FPC runner/apt: gate уже виконується у fpc-headless.
# Python-свідки є механічними host-тестами ELF, не переписом SENS у Python.
timeout 45s python3 scripts/test-native-elf-evidence.py >"$LOG" 2>&1
COUNT="$(sed -nE 's/^Ran ([0-9]+) tests? in .*/\1/p' "$LOG" | tail -n 1)"
if [[ ! "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 17 )); then
  echo "НАТИВНИЙ-ELF-ГЕЙТ-БЛОК: втрачено машинні тести (виконано: ${COUNT:-0})" >&2
  exit 1
fi
if ! grep -Fxq 'OK' "$LOG" || grep -Eq 'skipped=|^FAILED|^ERROR' "$LOG"; then
  echo "НАТИВНИЙ-ELF-ГЕЙТ-БЛОК: пропущено або провалено host-тести" >&2
  exit 1
fi
echo "НАТИВНИЙ-ELF-ГЕЙТ-ГАРАЗД cases=$COUNT machine=linux-x86_64 oracle=NOT-CHECKED energy=NOT-MEASURED"
