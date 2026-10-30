#!/usr/bin/env bash
# G2.43: справжній Free Pascal — фізичне D10 зв'язування та старий W1..W9.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${FPC:=fpc}"
mkdir -p build/m0.2/test-units build/m0.2/bin
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$PWD/src" \
  -FU"$PWD/build/m0.2/test-units" -FE"$PWD/build/m0.2/bin" \
  -otest-binarybind-d10 "$PWD/scripts/test-binarybind-d10.pas"
./build/m0.2/bin/test-binarybind-d10
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$PWD/src" \
  -FU"$PWD/build/m0.2/test-units" -FE"$PWD/build/m0.2/bin" \
  -otest-binarybind "$PWD/scripts/test-binarybind.pas"
./build/m0.2/bin/test-binarybind
bash ./scripts/test-d2source.sh
