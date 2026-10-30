#!/usr/bin/env bash
# G6.231: один чинний FPC PR gate для двох прямих ExactIR→ELF64
# механізмів (D3:001 D1/D7 цитата, D3:010 D1 атомність).
# Фізична T5M відповідь перевіряється проти вже злитих backend.
# Жодного нового compiler/REPL, Rust/Zig, apt чи workflow.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash -n scripts/test-exactir-atom-priamyi.sh
bash -n scripts/test-exactirtoelf.sh
timeout 420s bash scripts/test-exactir-atom-priamyi.sh 2>"$TMP/test.err" | tee "$TMP/proof.log" || {
  cat "$TMP/test.err" >&2
  exit 1
}
grep -Fq 'ПРЯМИЙ-АТОМ-ТЕСТ-ГАРАЗД FPC=так машинні-ELF=3' "$TMP/proof.log"
grep -Fq 'write-відмов=6 відновлень=3' "$TMP/proof.log"
grep -Fq 'ДОВІРЕНИЙ-IR-ЕЛФ-ФІЗИЧНИЙ-ГАРАЗД Linux=x86-64 ELF=10' "$TMP/proof.log"
grep -Fq 'write-відмов=20 відновлень=10' "$TMP/proof.log"
echo 'EXACTIR-DIRECT-WRITE-PASS checked-FPC=1 quote-ELF=10 atom-ELF=3 host-write-negatives=26 recovery=13 semantic-oracle=NOT-RUN RAPL=NOT-MEASURED'
