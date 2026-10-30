#!/usr/bin/env bash
# G2.56 — pinned фізичні 129 DEFINE, exact D7 та round-trip, без eval.
# Вхід: тільки канонічний T5M із external/sens; вихід — механічні CI свідки.
# Lifetime: два послідовні FPC-процеси, stdout лишається у shell-пам'яті.
# Питання: 1) Чому цей тест не доводить виконання Core1?
# 2) Чому номер 130 — негативна межа, а не SENS-число?
# 3) Чому дві локалі не змінюють фізичну D7 ідентичність?
# 4) Чому недійсний .sens має відмовити без часткового stdout?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v timeout >/dev/null || {
  echo 'CORE1-ІНДЕКС-ВЕРИФІКАЦІЯ-БЛОК: немає timeout' >&2
  exit 127
}
run_exact() {
  local script="$1" marker="$2" output count
  if ! output="$(timeout 360s bash "$ROOT/scripts/$script" 2>&1)"; then
    printf '%s\n' "$output" >&2
    echo "CORE1-ІНДЕКС-ВЕРИФІКАЦІЯ-ПРОВАЛ: $script" >&2
    return 1
  fi
  count="$(printf '%s\n' "$output" | grep -Fxc -- "$marker" || true)"
  if [[ "$count" != 1 ]]; then
    printf '%s\n' "$output" >&2
    echo "CORE1-ІНДЕКС-ВЕРИФІКАЦІЯ-ПРОВАЛ: точний свідок $script count=$count" >&2
    return 1
  fi
  printf '%s\n' "$marker"
}
run_exact test-core1-indeks.sh \
  'CORE1-ІНДЕКС-ТЕСТ-ГАРАЗД pinned=129 exact-D7=так пошук=байтовий негативні=9 відновлення=так виконання=ні'
run_exact test-core1-otochennia.sh \
  'CORE1-ОТОЧЕННЯ-ГАРАЗД FPC=так exact-D7=1,48,129 фізичний-T5M=побайтово локалі=2 часові-пояси=2 український-шлях=так відмови=2 відновлення=так виконання=ні'
echo 'VERIFIED-CORE1-INDEX-PASS FPC=checked physical-DEFINE=129 exact-D7=129 locales=2 negatives=11 recovery=yes oracle=NOT-RUN energy=NOT-MEASURED'
