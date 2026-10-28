#!/usr/bin/env bash
# G1.4 physical transport CLI smoke, NOT language semantic parity.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN="${FPC:-fpc}"
BUILD="$ROOT/build/m0.2"
mkdir -p "$BUILD/bin" "$BUILD/t5mcli-units"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$BUILD/t5mcli-units" -FE"$BUILD/bin" -osenst5m "$ROOT/src/senst5m.lpr"
CLI="$BUILD/bin/senst5m"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '10 01\n' > "$tmp/input.words"
printf '\144' > "$tmp/expected.sens"
"$CLI" --pack-words "$tmp/input.words" > "$tmp/actual.sens"
cmp "$tmp/expected.sens" "$tmp/actual.sens"
"$CLI" --view "$tmp/expected.sens" > "$tmp/view.words"
cmp "$tmp/input.words" "$tmp/view.words"

printf '10 00 01\n' > "$tmp/multi.words"
printf '\143\263' > "$tmp/multi.sens"
"$CLI" --pack-words "$tmp/multi.words" > "$tmp/packed.sens"
cmp "$tmp/multi.sens" "$tmp/packed.sens"
"$CLI" --view "$tmp/packed.sens" > "$tmp/actual.words"
cmp "$tmp/multi.words" "$tmp/actual.words"

printf '000000000\n' > "$tmp/zeros.words"
"$CLI" --pack-words "$tmp/zeros.words" > "$tmp/zeros.sens"
"$CLI" --view "$tmp/zeros.sens" > "$tmp/zeros-recovered.words"
cmp "$tmp/zeros.words" "$tmp/zeros-recovered.words"

bad_case() {
  local title=$1 option=$2 input=$3
  if "$CLI" "$option" "$input" >"$tmp/fail.stdout" 2>"$tmp/fail.stderr"; then
    echo "T5M-CLI-FAIL accepted $title" >&2
    exit 1
  fi
  test ! -s "$tmp/fail.stdout" || { echo "T5M-CLI-FAIL partial stdout $title" >&2; exit 1; }
  grep -q 'SENST5M-FAIL' "$tmp/fail.stderr" || { echo "T5M-CLI-FAIL missing error $title" >&2; exit 1; }
}
printf '10  01\n' > "$tmp/double-space.words"
printf ' 10\n' > "$tmp/leading-space.words"
printf '10 \n' > "$tmp/trailing-space.words"
printf '10 01' > "$tmp/missing-lf.words"
printf '10 2\n' > "$tmp/trit.words"
printf '10\t01\n' > "$tmp/tab.words"
printf '10\r\n' > "$tmp/crlf.words"
printf '' > "$tmp/empty.words"
printf '\363' > "$tmp/bad-byte.sens"
printf '\242' > "$tmp/leading-separator.sens"
printf '\362' > "$tmp/only-padding.sens"

bad_case 'double space' --pack-words "$tmp/double-space.words"
bad_case 'leading space' --pack-words "$tmp/leading-space.words"
bad_case 'trailing space' --pack-words "$tmp/trailing-space.words"
bad_case 'missing LF' --pack-words "$tmp/missing-lf.words"
bad_case 'separator in bit word' --pack-words "$tmp/trit.words"
bad_case 'tab' --pack-words "$tmp/tab.words"
bad_case 'CRLF' --pack-words "$tmp/crlf.words"
bad_case 'empty input' --pack-words "$tmp/empty.words"
bad_case 'missing input' --pack-words "$tmp/does-not-exist.words"
bad_case 'forbidden byte 243' --view "$tmp/bad-byte.sens"
bad_case 'leading separator' --view "$tmp/leading-separator.sens"
bad_case 'only padding' --view "$tmp/only-padding.sens"
echo 'SENST5M-CLI-OK fpc=real golden-bytes=2 roundtrip=3 negatives=12 stdout=byte-exact execution=NOT_PROVEN'
