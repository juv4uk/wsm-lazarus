#!/usr/bin/env bash
# G6.229: фізичний D3:110 T5M writer мусить порівнювати Linux
# sys_write RAX з одним байтом. Чинний FPC PR gate підхоплює цей скрипт
# без нової важкої збірки Rust/Zig, install чи workflow.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash -n scripts/test-elfcondt5m.sh
timeout 240s bash scripts/test-elfcondt5m.sh | tee "$TMP/умова.log"
grep -Fq 'COND-T5M-ADMISSION-PASS positives=9 negatives=9' "$TMP/умова.log"
grep -Fq 'ФІЗИЧНА-МАШИННА-УМОВА-ГАРАЗД ELF=9' "$TMP/умова.log"
grep -Fq 'write-відмов=18 відновлень=9' "$TMP/умова.log"
echo 'COND-T5M-WRITE-PASS FPC=checked physical-ELF=9 admission-negative=9 host-write-negative=18 recovery=9 oracle=NOT-RUN energy=NOT-MEASURED'
