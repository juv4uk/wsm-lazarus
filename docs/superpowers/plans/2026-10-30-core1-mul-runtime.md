# Runtime-множення pinned Core1 — план реалізації

> Виконую локально у поточному `main`, оскільки власник явно доручив працювати й завершувати вертикальні зрізи в `main`.

**Мета:** побудувати один перевірений Linux x86-64 ELF для фізичного визначення `ядро1-помножити`, який приймає дві runtime D12 T5M величини та віддає точний D12 або D24 результат.

**Архітектура:** нова функція в `wsm.lowerpinnedcore1mul` повторно перевіряє оригінальний Core1 `.sens`, витягає точну фізичну голову та формує фізичний D5 якір із двома тестовими аргументами. Статичний Core1 результат має збігтися з адаптивним ELF, який побудовано лише чинними `BuildAdaptiveD12MulStreamELF` і pinned WideIR. Саме тіло множення лишається у перевіреному нативному backend.

**Стек:** Free Pascal 3.2.2, T5M/WideIR, Linux x86-64 ELF64, pinned SENS 12.0 CLI oracle.

**Авторитет:** `external/sens` на pinned SHA з `refs/tier1-baseline.properties`; фізичний `lib/core1.sens`, Contract 12.0 та чинні D5/D12/D24 механізми.

**Інтерфейс:** `BuildPinnedCore1MulStreamELF(const RepoRoot: String; const LeftPhysical, RightPhysical: RawByteString): RawByteString` повертає володіючий ELF64 образ; операнди — позичені canonical T5M D12 atoms; значення часу виконання передаються двома окремими 3-байтовими кадрами через stdin.

## Глобальні обмеження

- Числова драбина починається з D12; promotion і фізичний результат мають дотримуватися pinned numeric plane.
- Не виводити закон із текстового spelling, ширини чи числа; не переписувати бібліотечне Core1 тіло на Pascal.
- Невідомі/неприпустимі форми й входи відхиляти; зберігати діагностику та негативні перевірки.
- ELF — вузький AOT-профіль, не твердження про повне виконання Core1.

## Файли

- Зміна: `src/wsm.lowerpinnedcore1mul.pas` — API для source-backed Core1 multiply stream ELF.
- Нові: `src/senscore1mulpotikelf.lpr`, `scripts/test-core1mulpotikfixtures.pas`, `scripts/test-core1mulpotikelf.sh`, `.github/workflows/core1-mul-runtime.yml`.

## Основні ризики та тести

1. Core1 визначення змінене або неоднозначне: test fixture має довести fail-closed admission.
2. Статичний pinned Core1 і адаптивний WideIR результат розходяться: один anchor перевіряється до публікації ELF.
3. ELF читає неканонічний/неповний кадр: наявні адаптивні негативи доповнюються CLI/profile regression.
4. D12 overflow має давати D24 без обрізання: перевірити окремо через SENS REPL oracle.
5. Людська проєкція не повинна входити до compiler input: передавати лише фізичні T5M байти.

## Кроки

### Крок 1: API і RED

Додати тестовий Pascal consumer, який очікує `BuildPinnedCore1MulStreamELF(RepoRoot, LeftAnchor, RightAnchor): RawByteString`, збирає ELF і звіряє статичний anchor через `PinnedCore1MulCall`. Запустити перед реалізацією й підтвердити очікувану помилку відсутнього API.

- [x] **RED:** тестовий споживач спершу не збирався: FPC видав `Identifier not found "BuildPinnedCore1MulStreamELF"`.

### Крок 2: мінімальна реалізація

У `wsm.lowerpinnedcore1mul` повторно використати приватне фізичне admission `ExtractPinnedMultiplication`, побудувати D5 T5M anchor з витягнутим `HeadBits`, перевірити результат `PinnedCore1MulCall` та передати anchor на наявний `BuildAdaptiveD12MulStreamELF`. Відхилити порожній ELF і непідтверджену геометрію.

- [x] **GREEN:** checked FPC consumer зібрався й запустив нову source-backed API після реалізації.

### Крок 3: CLI та fixtures

Додати український CLI з точними двома фізичними D12 anchor файлами та no-clobber вихідним ELF. Паскаль fixtures генерують кілька runtime 6-byte frames (включно з негативними/нульовими/промотованими добутками), а SENS REPL oracle очікування створює окремо. Перевірити ELF-компіляцію, повторне використання одного образу, результатні ширини та негативи.

- [x] CLI, fixtures та негативи реалізовані; профільний тест звірив 16 runtime-випадків із SENS REPL, перевірив 8 D12/8 D24, no-clobber і повторне використання одного байт-в-байт тотожного ELF. Fixture також напряму звіряє Core1 physical result із канонічним фізичним кодуванням десяткового очікування. Негатив підміняє D5 голову в canonical `core1.sens` і перевіряє fail-closed admission. Core1 evaluator/numeric plane є consistency witness, а не незалежним oracle.

### Крок 4: інтеграційне підтвердження

Додати окремий workflow із pinned SENS checkout/build, checked FPC, профільним тестом та загальним `scripts/test.sh`. Запустити локальні перевірки й актуальний GitHub Actions на точному SHA; виправляти тільки підтверджені помилки з тестом RED→GREEN.

- [x] На локальній основі `3339e5f`: новий профільний тест, існуючий adaptive multiply regression та `scripts/test.sh` пройшли. Workflow path filter охоплює parser, exact binder, Core1 runtime, WideIR та ELF залежності.

### Крок 5: commit і звіт

Переглянути diff/конфлікти, коміт українською, push до `main`, дочекатися точного CI і записати звіт у #47. CLAIM звільнити лише після доказу.
