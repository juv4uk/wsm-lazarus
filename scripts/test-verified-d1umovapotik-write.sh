#!/usr/bin/env bash
# G6 — обов'язковий PR FPC свідок машинного stdout динамічної D3:110.
# Використовує один уже наявний генератор/тест, не створює нового reader,
# закону SENS, FPC runner, Rust/Zig компіляції чи окремого workflow.
# Ім'я test-verified-*.sh автоматично підхоплює test-verified-all.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash -n scripts/test-d1umovapotik.sh
timeout 240s bash scripts/test-d1umovapotik.sh | tee "$TMP/результат.log"
grep -Fq 'Д1-УМОВА-ПОТІК-ГАРАЗД фізичних=16 перша=8 друга=4 вичерпано=4' "$TMP/результат.log"
grep -Fq 'негативів=11 write-відмов=32 відновлень=16' "$TMP/результат.log"
echo 'Д1-УМОВА-WRITE-PASS FPC=checked ELF64=1 machine-positives=16 admission-negatives=11 host-write-negatives=32 recovery=16 oracle=OPTIONAL energy=NOT_MEASURED'
