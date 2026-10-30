#!/usr/bin/env bash
# G6 — регресія фізичного D12/D24 NEG для спільного FPC PR gate.
# Перевикористовує чинні canonical T5M свідки й машинний ELF тест.
# Це Linux ABI доказ, не новий закон SENS і не вимірювання енергії.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
command -v timeout >/dev/null || { echo 'Д12-NEG-CI-БЛОК: немає timeout' >&2; exit 127; }
command -v mktemp >/dev/null || { echo 'Д12-NEG-CI-БЛОК: немає mktemp' >&2; exit 127; }
[[ -c /dev/full ]] || { echo 'Д12-NEG-CI-БЛОК: немає Linux /dev/full' >&2; exit 127; }
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
if ! timeout 240s bash scripts/test-elfneg-write.sh >"$LOG" 2>&1; then
  tail -n 50 "$LOG" >&2
  echo 'Д12-NEG-CI-ПРОВАЛ: реальна збірка або ELF64 виконання не пройшли' >&2
  exit 1
fi
if ! grep -Fq 'machine=10 closed=10 full=10 recovery=10 D24=1' "$LOG"; then
  tail -n 50 "$LOG" >&2
  echo 'Д12-NEG-CI-ПРОВАЛ: неповна матриця фізичних свідків' >&2
  exit 1
fi
grep -F 'Д12-NEG-ЗАПИС-ГАРАЗД' "$LOG"
echo 'VERIFIED-D12NEG-WRITE-PASS elf=10 closed=10 full=10 recovery=10 d24=1 oracle=NOT-RUN energy=NOT-MEASURED'
