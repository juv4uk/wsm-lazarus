#!/usr/bin/env bash
# G6.147 — real FPC binary, independent pinned SENS callability,
# positive machine ELF64 T5M and semantic NOT-CALLABLE negatives.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
 echo 'ОРАКУЛ-ПЕРШИЙ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in timeout fpc git cmp readelf grep mktemp sha256sum python3; do
 command -v "$t" >/dev/null || { echo "бракує $t" >&2;exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test -n "${SENS_ORACLE_BIN:-}" && test -x "$SENS_ORACLE_BIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
trap 'rc=$?;if ((rc!=0));then
 echo "ОРАКУЛ-ПЕРШИЙ-ТЕСТ-ПРОВАЛ rc=$rc" >&2
 for f in "$TMP"/*.err "$TMP"/*.log;do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 30 "$f" >&2; }
 done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/physical" "$TMP/uc" "$TMP/ug" "$TMP/un"
for spec in \
 'src/senswidefrontelf.lpr senswidefrontelf uc' \
 'scripts/test-elfd12mulpotik.pas test-elfd12mulpotik ug' \
 'scripts/test-oracle-first-elf.pas test-oracle-first-elf un';do
 read -r file name units <<<"$spec"
 timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$name" \
  "$ROOT/$file" >"$TMP/$name.build.log" 2>&1 || {
   cat "$TMP/$name.build.log" >&2;exit 1;
  }
 test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd12mulpotik" "$TMP/physical" \
 >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'positive=26 d24=8 negatives=12' "$TMP/generator.log"
timeout 30s "$TMP/bin/test-oracle-first-elf" "$TMP/physical" \
 >"$TMP/negative-generator.log" 2>"$TMP/negative-generator.err"
grep -Fq 'ORACLE-FIRST-FIXTURES-OK negative-heads=2' \
 "$TMP/negative-generator.log"
export SENS_COMPILER_BIN="$TMP/bin/senswidefrontelf"
PASS=0;PROMOTE=0
while IFS=$'\t' read -r label left right expected;do
 test -n "$label"
 dest="$TMP/$label.elf"
 timeout 90s bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/$label.sens" "$dest" \
  >"$TMP/$label.out" 2>"$TMP/$label.err"
 test ! -s "$TMP/$label.err"
 grep -Fq 'callability=підтверджено' "$TMP/$label.out"
 test -x "$dest"
 readelf -h "$dest" | grep -Eq 'Type:.*DYN'
 timeout 5s "$dest" >"$TMP/$label.actual.sens" \
 2>"$TMP/$label.machine.err"
 test ! -s "$TMP/$label.machine.err"
 cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
 test "$(wc -c < "$TMP/$label.actual.sens")" -eq 3
 PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 26
while IFS=$'\t' read -r label left right expected;do
 test -n "$label"
 dest="$TMP/$label.elf"
 timeout 90s bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/$label.sens" "$dest" \
 >"$TMP/$label.out" 2>"$TMP/$label.err"
 test -x "$dest" && test ! -s "$TMP/$label.err"
 timeout 5s "$dest" >"$TMP/$label.actual.sens" \
 2>"$TMP/$label.machine.err"
 test ! -s "$TMP/$label.machine.err"
 cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected-d24.sens"
 test "$(wc -c < "$TMP/$label.actual.sens")" -eq 5
 PROMOTE=$((PROMOTE+1))
done <"$TMP/physical/overflows.tsv"
test "$PROMOTE" -eq 8
# Native byte identity with the original verified FPC compiler.
timeout 30s "$TMP/bin/senswidefrontelf" \
 --скомпілювати-фізичну-форму "$TMP/physical/03.sens" \
 "$TMP/03.direct.elf" >"$TMP/direct.log" 2>"$TMP/direct.err"
cmp "$TMP/03.direct.elf" "$TMP/03.elf"
# D6 has a resident projection but its whole D2 physical form is
# NOT callable under the pinned SENS law: must reject BEFORE ANY backend.
cat >"$TMP/fake-compiler" <<'EOF'
#!/bin/sh
printf 'ЗАБОРОНЕНИЙ-КОМПІЛЯТОР\n' >"$SENS_TEST_SENTINEL"
exit 0
EOF
chmod 700 "$TMP/fake-compiler"
NEG=0
reject() {
 local path="$1" name="$2" rc=0
 timeout 90s bash scripts/sens-oracle-first-elf.sh \
 "$path" "$TMP/reject-$NEG.elf" \
 >"$TMP/reject-$NEG.out" 2>"$TMP/reject-$NEG.err" || rc=$?
 test "$rc" -eq 2 && test ! -e "$TMP/reject-$NEG.elf"
 test ! -s "$TMP/reject-$NEG.out"
 grep -Fq 'ОРАКУЛ-ПЕРШИЙ-ВІДМОВА' "$TMP/reject-$NEG.err"
 if [[ "$name" == semantic ]];then
  grep -Fq 'domain identity is not callable under its ratified law' \
   "$TMP/reject-$NEG.err"
 fi
 NEG=$((NEG+1))
}
for opcode in 110100 110110;do
 export SENS_COMPILER_BIN="$TMP/fake-compiler"
 export SENS_TEST_SENTINEL="$TMP/forbidden-compiler-$opcode"
 reject "$TMP/physical/not-callable-$opcode.sens" semantic
 test ! -e "$SENS_TEST_SENTINEL"
done
export SENS_COMPILER_BIN="$TMP/bin/senswidefrontelf"
for file in wrong-domain-d7 bad-root bad-t5m empty;do
 reject "$TMP/physical/$file.sens" other
done
reject "$TMP/physical/projection.lisp" other
reject "$TMP/no-file.sens" other
test "$NEG" -eq 8
# Fail closed: missing pinned oracle, disallowed source, no-clobber and symlink.
rc=0
env -u SENS_ORACLE_BIN bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/01.sens" "$TMP/no-oracle.elf" \
 >"$TMP/no-oracle.out" 2>"$TMP/no-oracle.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/no-oracle.elf"
rc=0
env -u SENS_COMPILER_BIN bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/01.sens" "$TMP/no-compiler.elf" \
 >"$TMP/no-compiler.out" 2>"$TMP/no-compiler.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/no-compiler.elf"
cp "$TMP/03.elf" "$TMP/occupied.elf"
before="$(sha256sum "$TMP/occupied.elf" | cut -d' ' -f1)"
# Explicit occupied-target test, bypassing reject() (target fixed name).
rc=0
timeout 30s bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/01.sens" "$TMP/occupied.elf" \
 >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
test "$(sha256sum "$TMP/occupied.elf" | cut -d' ' -f1)" = "$before"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 30s bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/01.sens" "$TMP/dangling.elf" \
 >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/absent.elf"
timeout 90s bash scripts/sens-oracle-first-elf.sh \
 "$TMP/physical/07.sens" "$TMP/recovered.elf" \
 >"$TMP/recovered.log" 2>"$TMP/recovered.err"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.actual.sens"
cmp "$TMP/recovered.actual.sens" "$TMP/physical/07.expected.sens"
echo "ОРАКУЛ-ПЕРШИЙ-ГОТОВО: callable=$((PASS+PROMOTE)) d12=$PASS d24=$PROMOTE semantic-not-callable=2 negatives=$NEG no-clobber=так machine=ELF64 pinned=$PIN energy=NOT-MEASURED"
