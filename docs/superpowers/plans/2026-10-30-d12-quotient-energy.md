# Енергія холодного запуску D12-ділення — план реалізації

> Виконується поточним агентом у межах CLAIM G6.176; кожен крок перевіряється тут, без передачі іншому агенту.

**Мета:** виміряти на RAPL однакові холодні запуски вже зібраних SENS, C, Rust і Free Pascal виконавців фізичного D5-ділення з двома runtime D12.

**Архітектура:** використати наявний `sensd12quotpotikelf` як SENS ELF. Три порівняльні виконавці прийматимуть ті самі шість T5M байтів і повертатимуть той самий канонічний T5M результат. Оркестратор перед виміром перевіряє точні виходи, негативи, pinned SENS REPL та SHA артефактів; апаратні виміри окремо позначають пакетне споживання й не приписують його PID.

**Технології:** FPC, GCC, rustc, Python 3, Linux x86-64, наявний `sensrapl` та pinned SENS 12.0.

**Джерела:** `external/sens/contracts/language-contract-12.lisp`, `src/wsm.elfd12quotpotik.pas`, `scripts/energy/compare-four-elf.py`.

## Обмеження

- Канонічний вхід/вихід — packed T5M, а не текстова проєкція.
- Кожен мовний worker перевіряє повний кадр до будь-якого stdout.
- Усі мови виконують тільки exact integer signed D12-ділення; нуль, остача або D24-ріст відхиляються.
- RAPL вимірює пакет CPU та включає запуск, transport і ОС; це не енергія процесу чи повного компілятора.
- Автоматичний запуск тільки ручний (`workflow_dispatch`); жодних Rust-збірок на push/PR.
- Немає фізичного RAPL — немає джоулів у звіті.

## Файли

- `benchmarks/cross-language/quot/quot.c`, `.rs`, `.pas`: незалежні workers із тим самим фізичним stdin/stdout кадром.
- `scripts/energy/quot-runtime-benchmark.py`: T5M fixture, build/preflight, вимірювання, звіт із сирими вибірками.
- `scripts/energy/test-quot-runtime-benchmark.py`: позитивні/негативні кадри, parity і no-clobber.
- `scripts/energy/run-quot-runtime-benchmark.sh`: bounded local entrypoint.
- `.github/workflows/benchmark-d12-quot-energy.yml`: ручний функціональний gate без RAPL-твердження.
- `benchmarks/cross-language/quot/README.uk.md`: метод і фактичний результат, якщо локальний датчик доступний.

## Послідовність

1. Написати failing Python tests для точного T5M encode/decode та відмов.
2. Додати мінімальний host-кадрний кодек і побачити RED→GREEN.
3. Додати три незалежні native workers; зібрати кожен і перевірити однакові позитивні/негативні кадри проти SENS ELF та pinned REPL.
4. Додати bounded RAPL orchestration, розігрів, випадковий порядок, парні idle samples, raw JSONL і атомарну публікацію без перезапису.
5. Додати workflow лише з `workflow_dispatch`; виконати локальні тести, реальну збірку й RAPL лише за наявності читабельного датчика.

## Питання для огляду

- Чому пакетний RAPL не є енергією окремого процесу?
- Чому однакова T5M рамка краща за текстовий десятковий ввід для цього вузького порівняння?
- Чому D24 promotion і неціла частка мають відмовляти в усіх workers?
- Чому manual-only workflow не свідчить про відсутність локальної можливості вимірювати?
- Чому цей результат не ранжує цілі мови чи загальний компілятор?
