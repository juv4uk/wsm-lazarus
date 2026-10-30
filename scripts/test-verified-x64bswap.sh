#!/usr/bin/env bash
# G6.257 — вхід наявного host BSWAP до обов'язкового fpc-headless verified gate.
# Вхід: тільки stdout фактично виконаного scripts/test-x64bswap.sh.
# Вихід: один PASS після перевіреного FPC, GNU as, 9 негативів і 2 ELF64.
# Буфер REPORT живе тільки протягом цього shell-процесу; фізичних SENS
# значень, нових законів, окремого emitter чи енергетичних оцінок немає.
# Питання: 1) Чому цей wrapper не є компілятором SENS?
# 2) Чому GNU as є незалежним свідком opcode, а не мовним oracle?
# 3) Чому непройдений ELF має зупинити весь fpc-headless gate?
# 4) Чому stdout-підсумок перевіряємо лише після успішного exit дитини?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v timeout >/dev/null || {
  echo 'X64-BSWAP-БЛОК: відсутній timeout' >&2
  exit 127
}

# Зберігаємо реальний код відмови child, не видаємо PASS зі старого логу.
if ! REPORT="$(timeout 360s bash "$ROOT/scripts/test-x64bswap.sh")"; then
  printf '%s\n' "$REPORT" >&2
  echo 'VERIFIED-X64-BSWAP-FAIL: машинна перевірка завершилася з помилкою' >&2
  exit 1
fi
printf '%s\n' "$REPORT"

# Цей рядок друкується тільки ПІСЛЯ реальних GNU as cmp та запусків ELF64.
# Не допускаємо ні часткової, ні подвійної, ні спотвореної позначки успіху.
EXPECTED='X64-BSWAP-МАШИНА-ГАРАЗД 32 GNU-as parity; 9 negative; 2 ELF64; energy=NOT-MEASURED'
ACTUAL="$(printf '%s\n' "$REPORT" | grep -Fxc "$EXPECTED" || true)"
if [[ "$ACTUAL" != 1 ]]; then
  echo "VERIFIED-X64-BSWAP-FAIL: очікувався рівно один точний machine-pass, отримано $ACTUAL" >&2
  exit 1
fi
printf 'VERIFIED-X64-BSWAP-PASS FPC=checked GNU-as=32 negative=9 ELF64=2 energy=NOT-MEASURED\n'
