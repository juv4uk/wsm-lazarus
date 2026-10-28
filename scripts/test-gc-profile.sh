#!/usr/bin/env bash
# G7.7 bounded native FPC GC profile, NOT SENS semantic or energy admission.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=$(printenv FPC || printf 'fpc')
GIT_SHA=$(printenv GITHUB_SHA || printf 'unavailable')
UNIT_DIR="$ROOT/build/m0.2/gc-profile-units"
BIN_DIR="$ROOT/build/m0.2/bin"
mkdir -p "$UNIT_DIR" "$BIN_DIR"
command -v "$FPC_BIN" >/dev/null || { echo 'GC-PROFILE-FAIL fpc missing' >&2; exit 127; }
[[ -x /usr/bin/time ]] || { echo 'GC-PROFILE-FAIL GNU time missing' >&2; exit 127; }
"$FPC_BIN" -B -O2 -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-gc-profile "$ROOT/scripts/test-gc-profile.pas"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' \
  'GC-PROFILE-OK rounds=32 nodes=2048 allocations=65536 collections=64 slot-cap=2048 reclaimed=65536 stale=reject scope=pass' \
  > "$tmp/expected.stdout"
printf 'GC-PROFILE-ENV git_checkout=%s compiler=%s kernel=%s cpu=%s energy=ENERGY_NOT_MEASURED status=EXPLORATORY\n' \
  "$GIT_SHA" "$("$FPC_BIN" -iV)" "$(uname -srmo)" \
  "$(awk -F: '/model name/ {sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)"
for run in 1 2 3; do
  /usr/bin/time -f '%e %M %x' -o "$tmp/time.$run" \
    "$BIN_DIR/test-gc-profile" > "$tmp/stdout.$run" 2> "$tmp/stderr.$run"
  if ! cmp -s "$tmp/expected.stdout" "$tmp/stdout.$run"; then
    echo "GC-PROFILE-FAIL wrong output sample=$run" >&2
    cat "$tmp/stdout.$run" >&2
    exit 1
  fi
  if [[ -s "$tmp/stderr.$run" ]]; then
    echo "GC-PROFILE-FAIL unexpected stderr sample=$run" >&2
    cat "$tmp/stderr.$run" >&2
    exit 1
  fi
  read -r wall rss exit_code < "$tmp/time.$run"
  if [[ "$exit_code" != 0 || ! "$wall" =~ ^[0-9]+([.][0-9]+)?$ || ! "$rss" =~ ^[0-9]+$ ]]; then
    echo "GC-PROFILE-FAIL invalid time/RSS/exit sample=$run" >&2
    exit 1
  fi
  printf 'GC-PROFILE-RAW run=%s wall_seconds=%s peak_rss_kib=%s exit=%s phase=cold-process\n' \
    "$run" "$wall" "$rss" "$exit_code"
done
cat "$tmp/expected.stdout"
echo 'GC-PROFILE-LIMITS sessions=1 ordering=fixed energy=ENERGY_NOT_MEASURED inference=NOT_VALIDATED'
