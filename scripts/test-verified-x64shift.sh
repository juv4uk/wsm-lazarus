#!/usr/bin/env bash
# G6.253 — підключити перевірені x86-64 зсуви й обертання до одного FPC gate.
# Тільки host ISA: мовні закони SENS визначає pinned external/sens.
# Типи: лічильники — shell-рядки, а фізичний машинний результат — T5M байти.
# Час життя: тимчасові ELF та FPC units видаляє чинний test-x64shift.sh.
# 1) Чому вихід FPC із '?'-маркерами не означає помилку машинних байтів?
# 2) Чому недостатньо звірити лише кількість ELF?
# 3) Чому 160 GNU-as форм є незалежним оракулом host opcode?
# 4) Чому це не незалежний SENS REPL oracle?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# Точне правило єдине: або оригінальна кирилиця, або лише конкретні
# ASCII '?' на місці 4+6 кириличних літер; ВСІ лічильники обов'язкові.
MARKER='^X64-(ЗСУВ-ГОТОВО|[?]{4}-[?]{6}) golden=8 negative=5 recovery=1 as=160 elf=10$'
positive=0
negative=0
for line in \
  'X64-ЗСУВ-ГОТОВО golden=8 negative=5 recovery=1 as=160 elf=10' \
  'X64-????-?????? golden=8 negative=5 recovery=1 as=160 elf=10'; do
  if ! printf '%s\n' "$line" | grep -Eq "$MARKER"; then
    echo 'X64-ЗСУВ-МАРКЕР-ПРОВАЛ: правильний свідок відхилено' >&2
    exit 1
  fi
  positive=$((positive+1))
done
for line in \
  'X64-????-?????? golden=8 negative=5 recovery=1 as=159 elf=10' \
  'X64-????-?????? golden=8 negative=5 recovery=1 as=160 elf=9' \
  'X64-????-?????? golden=8 negative=4 recovery=1 as=160 elf=10'; do
  if printf '%s\n' "$line" | grep -Eq "$MARKER"; then
    echo 'X64-ЗСУВ-МАРКЕР-ПРОВАЛ: спотворений свідок прийнято' >&2
    exit 1
  fi
  negative=$((negative+1))
done
[[ "$positive" -eq 2 && "$negative" -eq 3 ]]
# Наявний тест: checked FPC, HEAPTRC, 160 GNU as, 10 ELF64/T5M, 5 негативів.
timeout 390s bash "$ROOT/scripts/test-x64shift.sh"
echo 'VERIFIED-X64SHIFT-PASS FPC=checked GNU-as=160 ELF64=10 T5M=10 negative=5 recovery=1 marker-positive=2 marker-negative=3 oracle=HOST-ISA energy=NOT-MEASURED'
