#!/usr/bin/env bash
# G6.147 — зовнішній обов'язковий pinned SENS call-admission ДО ELF.
# Лише host оркестрація; не SENS interpreter, не новий compiler/registry.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'ОРАКУЛ-ПЕРШИЙ-ВІДМОВА: %s\n' "$1" >&2; exit 2; }
[[ $# == 2 ]] || fail 'виклик: sens-oracle-first-elf.sh канон.sens новий.elf'
for cmd in realpath mktemp timeout git cmp sha256sum readelf ln rm cp; do
  command -v "$cmd" >/dev/null || fail "бракує host інструмента $cmd"
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] ||
  fail 'потрібен Linux x86-64'
SOURCE="$(realpath -m -- "$1")"
# Для цілі нормалізуємо ЛИШЕ каталог: basename лінка не розв’язувати.
DEST="$(realpath -m -- "$(dirname -- "$2")")/$(basename -- "$2")"
[[ "$1" == *.sens && "$2" == *.elf ]] ||
  fail 'потрібні фізичний .sens вхід і .elf вихід'
[[ ! -L "$1" && -f "$SOURCE" && ! -L "$SOURCE" && -r "$SOURCE" ]] ||
  fail 'вхідний canonical .sens не є доступним звичайним файлом'
[[ ! -e "$DEST" && ! -L "$DEST" ]] ||
  fail 'вихідний ELF уже існує; перезапис заборонено'
[[ -d "$(dirname -- "$DEST")" ]] || fail 'каталог виходу відсутній'
[[ -n "${SENS_ORACLE_BIN:-}" && -n "${SENS_COMPILER_BIN:-}" ]] ||
  fail 'не підключено pinned SENS oracle або наявний FPC compiler'
[[ -x "$SENS_ORACLE_BIN" && -x "$SENS_COMPILER_BIN" ]] ||
  fail 'oracle або compiler не є виконуваним файлом'
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
cd "$ROOT"
[[ -d sens-oracle/.git ]] ||
  fail 'відсутні pinned Git-походження SENS'
[[ "$(git -C external/sens rev-parse HEAD 2>/dev/null)" == "$PIN" ]] ||
  fail 'мовний авторитет не збігається з pinned SENS 12.0'
[[ "$(git -C sens-oracle rev-parse HEAD 2>/dev/null)" == "$PIN" ]] ||
  fail 'зовнішній SENS oracle не збігається з pinned SHA'
[[ "$(realpath -e -- "$SENS_ORACLE_BIN")" ==
   "$(realpath -e -- "$ROOT/sens-oracle/target/debug/sens")" ]] ||
  fail 'виконуваний oracle не походить зі зібраного pinned дерева'
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp ||
  fail 'не підтверджено Contract 12.0'
# Мовну ідентичність НЕ виводимо з фізичної довжини або host імені.
# Незалежний SENS CLI виконує саме повну копію фізичного source.
TMP="$(mktemp -d -- "$(dirname -- "$DEST")/.sens-dopus-XXXXXXXX")" ||
  fail 'не створено приватний каталог'
trap 'rm -rf -- "$TMP"' EXIT
cp -- "$SOURCE" "$TMP/program.sens" ||
  fail 'фізичне джерело не скопійовано'
[[ -s "$TMP/program.sens" ]] || fail 'порожня фізична програма'
[[ "$(wc -c < "$TMP/program.sens")" -le 65536 ]] ||
  fail 'фізичне джерело за квотою'
cmp "$SOURCE" "$TMP/program.sens" ||
  fail 'фізичні байти змінилися під час копіювання'
if ! timeout 60s "$SENS_ORACLE_BIN" "$TMP/program.sens" \
    >"$TMP/oracle.stdout" 2>"$TMP/oracle.stderr"; then
  if [[ -s "$TMP/oracle.stderr" ]]; then
    tail -c 850 "$TMP/oracle.stderr" >&2
    printf '\n' >&2
  fi
  fail 'pinned SENS відхилив виклик повної фізичної форми'
fi
[[ -s "$TMP/oracle.stdout" && ! -s "$TMP/oracle.stderr" ]] ||
  fail 'oracle не підтвердив завершений семантичний результат'
# Лише ТЕПЕР працює чинний FPC → WideIR → ELF64 emitter.
# PublishNewELF64 у приватному каталозі вже гарантує no-clobber.
if ! timeout 30s "$SENS_COMPILER_BIN" \
  --скомпілювати-фізичну-форму "$TMP/program.sens" "$TMP/native.elf" \
  >"$TMP/compiler.stdout" 2>"$TMP/compiler.stderr"; then
  if [[ -s "$TMP/compiler.stderr" ]]; then
    tail -c 850 "$TMP/compiler.stderr" >&2
    printf '\n' >&2
  fi
  fail 'наявний FPC compiler не допустив фізичний source'
fi
[[ -x "$TMP/native.elf" && ! -L "$TMP/native.elf" ]] ||
  fail 'компілятор не створив повний ELF64'
readelf -h "$TMP/native.elf" >"$TMP/header" ||
  fail 'не прочитано машинний ELF64'
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header" ||
  fail 'результат не ELF64 PIE'
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header" ||
  fail 'машина не x86-64'
[[ ! -s "$TMP/compiler.stderr" ]] ||
  fail 'компілятор повернув успіх із діагностикою помилки'
[[ ! -e "$DEST" && ! -L "$DEST" ]] ||
  fail 'хтось уже створив вихідний ELF'
ln -- "$TMP/native.elf" "$DEST" || fail 'атомарна no-clobber публікація не вдалася'
printf 'ОРАКУЛ-ПЕРШИЙ-ELF-ГОТОВО: pinned=%s callability=підтверджено machine=ELF64-PIE\n' "$PIN"
