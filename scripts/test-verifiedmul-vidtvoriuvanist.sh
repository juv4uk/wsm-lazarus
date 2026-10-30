#!/usr/bin/env bash
# G6.201 — відтворюваність справжнього D5 IMUL ELF64 для -O1/-O2.
# Розділені збірки й приватна тека; тільки FPC, без Rust/Zig/GPU.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VMR-БЛОК: немає FPC' >&2; exit 127; }
test -f "$ROOT/external/sens/lib/domains/d5.lisp" || {
  echo 'VMR-БЛОК: немає pinned SENS' >&2
  exit 66
}
TMP_BASE=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
TMP=$(mktemp -d "$TMP_BASE/sens-vmr.XXXXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/units1" "$TMP/units2" "$TMP/bin1" "$TMP/bin2" "$TMP/output1" "$TMP/output2"
for OPT in 1 2; do
  echo "VMR-ЗБІРКА FPC -O${OPT}"
  timeout 240s "$FPC_BIN" -B "-O${OPT}" -Mobjfpc -Fu"$ROOT/src" \
    -FU"$TMP/units${OPT}" -FE"$TMP/bin${OPT}" \
    -otest-vmr "$ROOT/scripts/test-verifiedmul-vidtvoriuvanist.pas"
  timeout 120s "$TMP/bin${OPT}/test-vmr" "$ROOT/external/sens" "$TMP/output${OPT}"
done
for I in 01 02 03 04 05 06 07 08; do
  for SUFFIX in elf expected.sens program.sens; do
    cmp "$TMP/output1/case${I}.${SUFFIX}" "$TMP/output2/case${I}.${SUFFIX}" || {
      echo "VMR-ЗБІЙ: різні байти -O1/-O2 для case${I}.${SUFFIX}" >&2
      exit 1
    }
  done
  for OPT in 1 2; do
    ELF="$TMP/output${OPT}/case${I}.elf"
    chmod 700 "$ELF"
    timeout 5s "$ELF" </dev/null >"$TMP/native.out" 2>"$TMP/native.err" || {
      echo "VMR-ЗБІЙ: machine ELF case${I} -O${OPT} завершився помилкою" >&2
      exit 1
    }
    test ! -s "$TMP/native.err" || {
      echo "VMR-ЗБІЙ: machine stderr case${I} -O${OPT}" >&2
      exit 1
    }
    cmp "$TMP/native.out" "$TMP/output${OPT}/case${I}.expected.sens" || {
      echo "VMR-ЗБІЙ: фізичний stdout case${I} -O${OPT} різний" >&2
      exit 1
    }
  done
  echo "VMR-OK case${I}: ідентичний ELF, 2 машинні виконання, точний T5M"
done
echo 'VMR-REPRO-PASS elfs=16 identical-pairs=8 physical-stdout=16'
