#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/m0.2"
mkdir -p "$BUILD/units" "$BUILD/bin"
fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$BUILD/units" -FE"$BUILD/bin" -osensc "$ROOT/src/sensc.lpr"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$BUILD/bin/sensc" --compile-ir "$ROOT/external/sens/lib/core4.lisp" "$tmp/one.sir"
"$BUILD/bin/sensc" --compile-ir "$ROOT/external/sens/lib/core4.lisp" "$tmp/two.sir"
cmp "$tmp/one.sir" "$tmp/two.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/one.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/two.sir"
# G6.2: statistics are structural-only and MUST be deterministic.
"$BUILD/bin/sensc" --inspect-ir "$tmp/one.sir" > "$tmp/one.stats"
"$BUILD/bin/sensc" --inspect-ir "$tmp/two.sir" > "$tmp/two.stats"
cmp "$tmp/one.stats" "$tmp/two.stats"
grep -Eq 'tokens=[1-9][0-9]*' "$tmp/one.stats"
grep -Eq 'opens=[1-9][0-9]*' "$tmp/one.stats"
grep -Eq 'payload_bytes=[1-9][0-9]*' "$tmp/one.stats"
grep -Eq 'max_depth=[1-9][0-9]*' "$tmp/one.stats"

# SIR1 fixtures are mechanical corruption tests, not SENS semantic laws.
printf 'SIR1\000\000\000\000\000' > "$tmp/empty-ok.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/empty-ok.sir"
"$BUILD/bin/sensc" --inspect-ir "$tmp/empty-ok.sir" > "$tmp/empty.stats"
test "$(cat "$tmp/empty.stats")" = 'SENSC-SIR1-INSPECT-OK structural-only=1 tokens=1 opens=0 closes=0 atoms=0 strings=0 payload_bytes=0 max_depth=0'
printf 'BIR1\000\000\000\000\000' > "$tmp/bad-magic.sir"
printf 'SIR1' > "$tmp/missing-end.sir"
printf 'SIR1\007\000\000\000\000' > "$tmp/bad-opcode.sir"
printf 'SIR1\001\000\000\000\000\000\000\000\000\000' > "$tmp/unclosed.sir"
printf 'SIR1\002\000\000\000\000\000\000\000\000\000' > "$tmp/extra-close.sir"
printf 'SIR1\003\007\000\000\000ab' > "$tmp/truncated.sir"
printf 'SIR1\004\001\000\000\000x\000\000\000\000\000' > "$tmp/bad-string.sir"
printf 'SIR1\001\001\000\000\000x\000\000\000\000\000' > "$tmp/bad-struct.sir"
printf 'SIR1\000\001\000\000\000x' > "$tmp/bad-end.sir"
cp "$tmp/one.sir" "$tmp/trailing.sir"
printf 'x' >> "$tmp/trailing.sir"
for bad in bad-magic missing-end bad-opcode unclosed extra-close truncated bad-string bad-struct bad-end trailing; do
  if "$BUILD/bin/sensc" --verify-ir "$tmp/$bad.sir"; then
    echo "SENSC-FAIL corrupt SIR1 accepted: $bad" >&2
    exit 1
  fi
  if "$BUILD/bin/sensc" --inspect-ir "$tmp/$bad.sir" > "$tmp/invalid.stats"; then
    echo "SENSC-FAIL corrupt SIR1 inspection accepted: $bad" >&2
    exit 1
  fi
done
printf '(незакрите' > "$tmp/bad.lisp"
if "$BUILD/bin/sensc" --compile-ir "$tmp/bad.lisp" "$tmp/bad.sir"; then
  echo 'SENSC-FAIL malformed source accepted' >&2
  exit 1
fi
test ! -e "$tmp/bad.sir"
echo 'SENSC-IR-TEST-OK deterministic=1 malformed=reject verifier=12-cases inspector=corrupt-reject stats=deterministic'
# GE.10: швидкі негативи точного RAPL host-протоколу у чинному FPC gate.
# У GitHub CI відсутність RAPL не стає вигаданими джоулями.
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/scripts/energy/test_measure.py"
# G7.1: independent heap-mechanism test; does not confer SENS law authority.
bash "$ROOT/scripts/test-gc.sh"

# G1.2: physical T5M .sens transport test; neither SENS law nor Core4 execution.
fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$BUILD/units" \
  -FE"$BUILD/bin" -otest-t5m "$ROOT/scripts/test-t5m.pas"
(cd "$ROOT" && "$BUILD/bin/test-t5m")
# G5.1 independent session mechanism, not a SENS semantic evaluator.
bash "$ROOT/scripts/test-session.sh"

# G6.168/G6.200: механічні нативні ELF-регресії з одним FPC-встановленням.
# Вхід: фізичні T5M з pinned authority; вихід: машинні ELF і побайтові докази.
# Кожен harness керує власним mktemp та прибирає його під час завершення.
# Це НЕ нові закони SENS і НЕ незалежний REPL-oracle для всіх D3 форм.
# 1. Чому обидва профілі мають запускатися з одного PR FPC runner?
# 2. Чим фізичне виконання ELF відрізняється від паритету SENS REPL?
# 3. Чому ручні окремі workflow не відключені?
# 4. Які негативи захищають malformed T5M та machine stdout?
bash "$ROOT/scripts/test-irwide-d3-elf.sh"
bash "$ROOT/scripts/test-widepotikelf.sh"
# G6.205: зберегти двійковий D5:10110 в одному verified WideIR.
# Той самий FPC PR runner, без другого workflow або незалежної інсталяції.
# Справжні executable T5M stdin/output, негативи й порівняння proof ELF.
bash "$ROOT/scripts/test-mulstream-context.sh"
# G6.171: новий машинний D4:0100(D5:01000(D12)) через наявний FPC PR-job.
# Ручний oracle workflow збережено; тут лише швидка машина та фізичні негативи.
# 1. Чому не збираємо Rust/Zig у PR? 2. Чому stdout має бути точним D1?
# 3. Хто зберігає закон? 4. Чому SETNE перевіряємо дизасемблером?
SENS_VERIFY_MODE=native-only SENS_ORACLE_BIN="" bash "$ROOT/scripts/test-irwidenenul.sh"

# G6.207 — один короткий FPC/backend build, фізичні CQO/IDIV ELF,
# негативи закритого fd1 і перевірка повного 3-байтового sys_write.
# Не новий SENS закон чи загальний evaluator; без окремого FPC workflow.
# 1) Чому `write` без перевірки RAX не є proof of execution?
# 2) Чому 3 байти — точний T5M D12 і не людська проєкція?
# 3) Чому fd1-закритий має завершитися host code=2?
# 4) Хто видаляє тимчасові ELF після негативів?
timeout 240s bash "$ROOT/scripts/test-elfquot-write.sh"
# G6: x86-64 FPC assembler/ABI свідок над host-байтами canonical T5M.
# Два isolated FPC -O1/-O2, справжній BSWAP RAX, 1024×2 parity.
# Ніякого нового reader, закону SENS чи окремого Rust/Zig/apt CI.
# Чому цю механічну вправу не називаємо швидшим backend до вимірювання?
timeout 240s bash "$ROOT/scripts/test-fpc-inline-t5m.sh"

# G6.210 — перевірка реального write(1,rsp,3) для signed D12 ADD ELF64.
# Використовує наявний FPC runner, жодної додаткової компіляції Rust/Zig.
# Чотири позитивні T5M, чотири відмови закритого fd1 і чотири recovery.
# 1) Чому ELF повинен перевіряти RAX sys_write, а не просто exit(0)?
# 2) Де саме закривається fd1 і як перевіряється host exit=2?
# 3) Чому D12 байти не можна оцінювати через людську .lisp проєкцію?
# 4) Чому незалежний SENS oracle не підтверджує стан Linux stdout?
timeout 240s bash "$ROOT/scripts/test-elfadd-write.sh"

# G6.194: у фізичному LE32+T5M потоці короткий POSIX write/EINTR
# не має губити байти. Детермінований host-тест запускається до
# дорогого FPC/ELF з того самого CI, без Rust/Zig чи окремого runner.
# 1) Хто володіє memoryview і fd? 2) Чому write може бути коротким?
# 3) Чому нуль bytes-written — fail-closed? 4) Чому це не закон SENS?
timeout 15s python3 "$ROOT/scripts/test-add-context-compiler.py" --selftest-write

# G6.211 — один checked FPC backend для IMUL, точні D12 і D24 T5M,
# негатив закритого stdout і перевірка фактичного `write` count=3|5.
# Жодних нових GitHub Actions workflow, Rust/Zig або мовних законів.
# 1) Чому D24 має п'ять T5M байтів, а D12 — три?
# 2) Чому після sys_write не можна безумовно exit(0)?
# 3) Де фіксуємо відповідь лише після реального виконання IMUL?
# 4) Чому fd1-close перевіряє машину, а не семантичну SENS програму?
timeout 240s bash "$ROOT/scripts/test-elfmul-write.sh"

# G6.213 — додатковий машинний інваріант: після NEG результат T5M
# опубліковано лише коли Linux write повернув повні D12/D24 3|5 байтів.
# Один наявний FPC PR runner; не створюємо окремий apt/CI job.
# 1) Чому код 2 — host Linux статус, а не SENS D1?
# 2) Чому без NEG/CMP/JNE disasm не можна назвати це machine proof?
# 3) Хто визначає канонічні D12/D24 очікувані байти?
# 4) Чому ці тести не вимірюють джоулі?
timeout 240s bash "$ROOT/scripts/test-elfneg-write.sh"

# G6.213 — реальний x86-64 D3:101 EQ після sys_write мусить перевірити
# повний 1-байтовий T5M, а закритий fd1 завершувати лише exit(2).
# Чинний FPC PR runner; жодних додаткових installer, workflows чи Rust/Zig.
# 1) Чому CMP EAX,EDX захищає короткий запис?
# 2) Яка відмова має бути після Linux -EBADF?
# 3) Чому контрольні EQ значення беруться з pinned T5M?
# 4) Чому потрібен recovery після кожного негативу?
timeout 240s bash "$ROOT/scripts/test-elfeqt5m.sh"

# G6.214: x86-64 signed D12 CMP/SETL фізично публікує рівно 1 D1 T5M байт;
# fd1 closed або /dev/full => host exit(2), потім успішне відновлення.
# Без нового workflow, Rust/Zig чи дублювання SENS evaluator.
timeout 240s bash "$ROOT/scripts/test-elfless-write.sh"

# G6.215: signed D12 CMP/SETG → точний D1 T5M лише після повного
# Linux sys_write. Ті самі 12 фізичних запусків і 9 admission негативів,
# плюс закритий stdout, /dev/full та відновлення. Без окремого workflow.
# 1) Чому signed SETG не замінюється перевіркою Linux write?
# 2) Чому RAX=1 є фізичним доказом публікації одного T5M байта?
# 3) Чому exit(2) є host відмовою, а не значенням D1?
# 4) Чому незалежний REPL oracle не підтверджує host I/O?
timeout 240s bash "$ROOT/scripts/test-elfd12bilsh.sh"

# G6.218 — реальні signed D12+D12→D24 ELF, повний write(1,rsp,5).
# 7 позитивів, 10 admission-негативів, 4 host write-негативи,
# 2 recovery. Той самий FPC PR runner, без нового workflow/важких мов.
timeout 240s bash "$ROOT/scripts/test-elfd12promote.sh"

# G6.218 D7 — реальний D3:101 W7×W7→D1 T5M із machine write(1).
# Чинний FPC runner: 2 ELF; 4 host I/O негативи; 2 recovery.
# Чому повний Linux sys_write не є новим законом SENS?
timeout 240s bash "$ROOT/scripts/test-elfd7eq-write.sh"

# G6.222 — один FPC→ELF64 пакет 32 signed D12 «більше?» над T5M.
# Позитиви, -EBADF/-ENOSPC та recovery: RAX sys_write має дорівнювати 32.
# Жодного нового CI workflow або SENS semantic registry.
# 1) Чому 32 D1 — 32 physical T5M bytes?
# 2) Чому перевірка ядра Linux не є мовним законом?
# 3) Чому після короткого write потрібен exit(2)?
# 4) Які виміри енергії ще не проведено?
timeout 240s bash "$ROOT/scripts/test-elfgreaterbatch32-write.sh"

# G6.225: фізичні D1:0/1 та D3:000 -> ELF64 ET_EXEC/ET_DYN.
# Точний pinned допуск, 10 host I/O відмов та 5 recovery з Linux.
# 1) Чому тут Linux exit(2) не є SENS D1?
# 2) Чому .sens лишається packed T5M, а stdout — історична проєкція?
# 3) Як FPC перевіряє ET_EXEC і ET_DYN?
# 4) Чому жодного нового Rust/Zig workflow?
timeout 240s bash "$ROOT/scripts/test-elfd1.sh"
