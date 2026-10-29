#!/usr/bin/env bash
# G6.128: один реальний CLI → 37 canonical .sens → 37 однакових native ELF.
# 4 simple D3 EQ, 16 nested EQ, 17 COND → SENS pinned Rust/Zig oracle.
# No semantic law or machine backend is reimplemented in this harness.
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo G6_128_BLOCK_NEEDS_LINUX_X86_64 >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump git mktemp grep head od; do
  command -v "$tool" >/dev/null || { echo "G6_128_BLOCK_MISSING_$tool" >&2;exit 127; }
done
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP="$(mktemp -d)"
trap 'status=$?; if ((status != 0)); then
  for file in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 90 "$file" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP"/{bin,units,eq,nested,cond,compiled}
build() {
  local src="$1" name="$2"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/build-$name.log" 2>&1 || {
      cat "$TMP/build-$name.log" >&2;exit 1;
    }
}
build src/sensd3kompiliator.lpr sensd3kompiliator
build scripts/test-ird3entry.pas test-ird3entry
build scripts/test-ircallwriter.pas test-ircallwriter
build scripts/test-irnestedeqcall.pas test-irnestedeqcall
build scripts/test-ircondcall.pas test-ircondcall
for test in test-ird3entry test-ircallwriter test-irnestedeqcall test-ircondcall; do
  case "$test" in
    test-ird3entry) args=() ;;
    test-ircallwriter) args=("$TMP/eq") ;;
    test-irnestedeqcall) args=("$TMP/nested") ;;
    test-ircondcall) args=("$TMP/cond") ;;
  esac
  HEAPTRC="log=$TMP/heap-$test.log" timeout 120s \
    "$TMP/bin/$test" "${args[@]}" >"$TMP/$test.log" 2>"$TMP/$test.err" || {
      cat "$TMP/$test.log" "$TMP/$test.err" >&2;exit 1;
    }
  grep -Fq '0 unfreed memory blocks' "$TMP/heap-$test.log"
done
grep -Fq 'G6_128_PASS PROFILE=3 PHYSICAL=7 NEGATIVE=17' "$TMP/test-ird3entry.log"
grep -Fq 'G6_107_OK ELF=4 PHYS_NEG=13 HOST_NEG=12' "$TMP/test-ircallwriter.log"
grep -Fq 'G6_119_OK ELF=16 NEG=18 CALLS=3 RET=1' "$TMP/test-irnestedeqcall.log"
grep -Fq 'G6_122_OK ELF=17 NEG=17 CALL_SITES=' "$TMP/test-ircondcall.log"
count=0
simple=0
nested=0
cond=0
for dir in eq nested cond; do
  for source in "$TMP/$dir"/*.sens; do
    [[ "$source" == *.expected.sens ]] && continue
    test -s "$source" || { echo G6_128_MISSING_SOURCE >&2;exit 1; }
    stem="${source%.sens}"
    name="${stem##*/}"
    expected="$stem.expected.sens"
    case "$dir" in
      eq) original="$stem.elf" ;;
      nested) original="$stem.elf" ;;
      cond) original="$stem.call.elf" ;;
    esac
    test -s "$original" && test -s "$expected"
    exe="$TMP/compiled/$dir-$name.elf"
    timeout 10s "$TMP/bin/sensd3kompiliator" --породити "$source" "$exe" \
      >"$TMP/cli.log" 2>"$TMP/cli.err"
    test ! -s "$TMP/cli.err"
    grep -Fq 'ELF64-байтів=' "$TMP/cli.log"
    test -x "$exe"
    cmp "$exe" "$original"
    timeout 8s readelf -h "$exe" >"$TMP/header.log"
    grep -Eq 'Type:.*DYN' "$TMP/header.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
    timeout 8s "$exe" >"$TMP/current.sens" 2>"$TMP/machine.err"
    test ! -s "$TMP/machine.err"
    cmp "$TMP/current.sens" "$expected"
    timeout 60s "$ORACLE" "$source" >"$TMP/oracle.txt" 2>"$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    case "$dir" in
      cond) cmp "$TMP/oracle.txt" "$stem.oracle.txt";cond=$((cond+1)) ;;
      eq)
        case "$name" in
          *00|*11) printf '1\n' >"$TMP/semantic.txt" ;;
          *01|*10) printf '0\n' >"$TMP/semantic.txt" ;;
          *) echo G6_128_UNEXPECTED_SIMPLE_NAME >&2;exit 1 ;;
        esac
        cmp "$TMP/oracle.txt" "$TMP/semantic.txt"
        simple=$((simple+1))
        ;;
      nested)
        bits="${name#d3-}"
        [[ "$bits" =~ ^[01]{4}$ ]] || { echo G6_128_BAD_NESTED_NAME >&2;exit 1; }
        left=0;right=0
        [[ "${bits:0:1}" == "${bits:1:1}" ]] && left=1
        [[ "${bits:2:1}" == "${bits:3:1}" ]] && right=1
        if ((left == right));then printf '1\n' >"$TMP/semantic.txt"
        else printf '0\n' >"$TMP/semantic.txt";fi
        cmp "$TMP/oracle.txt" "$TMP/semantic.txt"
        nested=$((nested+1))
        ;;
    esac
    count=$((count+1))
  done
done
test "$simple" -eq 4 && test "$nested" -eq 16 && test "$cond" -eq 17
test "$count" -eq 37
# CLI negative: do not publish a partial ELF, do not clobber existing files.
check_reject() {
  local code="$1";shift
  set +e
  timeout 8s "$TMP/bin/sensd3kompiliator" "$@" >"$TMP/reject.log" \
    2>"$TMP/reject.err"
  local result=$?
  set -e
  test "$result" -eq "$code" || {
    echo "G6_128_WRONG_REJECTION expected=$code actual=$result" >&2;exit 1;
  }
  test -s "$TMP/reject.err"
}
valid="$TMP/eq/рівність-11.sens"
test -s "$valid"
rejects=0
check_reject 64
rejects=$((rejects+1))
check_reject 64 --інше "$valid" "$TMP/compiled/wrong-flag.elf"
rejects=$((rejects+1))
check_reject 64 --породити "$valid" "$TMP/compiled/wrong-extension.txt"
rejects=$((rejects+1))
check_reject 64 --породити "$TMP/not.sens.txt" "$TMP/compiled/wrong-input.elf"
rejects=$((rejects+1))
check_reject 2 --породити "$TMP/not-found.sens" "$TMP/compiled/not-found.elf"
test ! -e "$TMP/compiled/not-found.elf"
rejects=$((rejects+1))
: >"$TMP/empty.sens"
check_reject 2 --породити "$TMP/empty.sens" "$TMP/compiled/empty.elf"
test ! -e "$TMP/compiled/empty.elf"
rejects=$((rejects+1))
printf '\363' >"$TMP/garbled.sens"
check_reject 2 --породити "$TMP/garbled.sens" "$TMP/compiled/garbled.elf"
test ! -e "$TMP/compiled/garbled.elf"
rejects=$((rejects+1))
head -c 65537 /dev/zero >"$TMP/oversize.sens"
check_reject 2 --породити "$TMP/oversize.sens" "$TMP/compiled/oversize.elf"
test ! -e "$TMP/compiled/oversize.elf"
rejects=$((rejects+1))
printf 'SENTINEL' >"$TMP/compiled/existing.elf"
check_reject 2 --породити "$valid" "$TMP/compiled/existing.elf"
test "$(cat "$TMP/compiled/existing.elf")" = SENTINEL
rejects=$((rejects+1))
ln -s "$TMP/compiled/missing-target" "$TMP/compiled/dangling.elf"
check_reject 2 --породити "$valid" "$TMP/compiled/dangling.elf"
test -L "$TMP/compiled/dangling.elf" && test ! -e "$TMP/compiled/dangling.elf"
rejects=$((rejects+1))
check_reject 2 --породити "$valid" "$TMP/missing-directory/output.elf"
test ! -e "$TMP/missing-directory/output.elf"
rejects=$((rejects+1))
check_reject 2 --породити "$valid" "$TMP/compiled/eq-рівність-11.elf"
rejects=$((rejects+1))
test "$(find "$TMP/compiled" -maxdepth 1 -name 'd3c*' | wc -l)" -eq 0
echo "G6_128_CLI_OK COMPLETE_PHYSICAL=37 EXECUTED_ELF=37 BASELINE_ELF_PARITY=37 PINNED_SENS=37 NEG_FPC=17 NEG_OLD=48 NEG_CLI=$rejects HEAP=ZERO ENERGY=NOT_MEASURED"
