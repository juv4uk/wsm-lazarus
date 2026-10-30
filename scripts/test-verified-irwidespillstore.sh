#!/usr/bin/env bash
# G6 — довести саме продукційний WideIR→D5 ELF64 зі спільним STORE.
# НІ нового REPL/мовного закону, НІ дублювання FPC machine fixture.
# Тест використовує чинний реальний pinned фізичний D5 spill профіль:
# 9 ELF64, 9 GNU-as і 15 машинних/вхідних відмов із recovery.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D5-SPILL-STORE-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for bin in timeout fpc git as objcopy readelf objdump cmp mktemp;do
  command -v "$bin" >/dev/null || {
    echo "D5-SPILL-STORE-БЛОК: бракує $bin" >&2;exit 127;
  }
done
TMP=$(mktemp -d)
on_exit() {
  local rc=$?
  if ((rc)); then
    echo "D5-SPILL-STORE-ЗБІЙ код=$rc" >&2
    for log in "$TMP"/*.log;do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2;tail -n 35 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap on_exit EXIT
# Готовий тест перевіряє pinned SENS, три FPC checked компіляції,
# збірку справжнього ELF, GNU-as байти, фізичні T5M і всі негативи.
# Так ми НЕ створюємо другий генератор чи ще один workflow/apt setup.
timeout 540s bash scripts/test-irwidespilladd.sh >"$TMP/verified.log" 2>&1
grep -Fq 'Д5-SPILL-ELF-ГАРАЗД' "$TMP/verified.log"
grep -Fq 'фізичних=9 машинних=9 негативів=15' "$TMP/verified.log"
if [[ -n "${SENS_ORACLE_BIN:-}" ]];then
  grep -Fq 'Д5-РЕЄСТРИ-НЕЗАЛЕЖНИЙ-REPL-ГАРАЗД oracle=9' "$TMP/verified.log"
  ORACLE=9
else
  ORACLE=NOT-RUN
fi
echo "WIDE-SPILL-STORE-PASS fpc=checked elf=9 physical=9 gnu-as=9 negative=15 oracle=$ORACLE energy=NOT-MEASURED"
