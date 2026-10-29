# Машинна математика SENS і RAPL — план реалізації

> **Виконання:** автономна реалізація у поточному сеансі; кроки перевіряти послідовно.

**Мета:** виміряти пакетну енергію двох наявних SSE2 та AVX2/FMA машинних ядер SENS на фізичному i5-6400, зберігши відтворювані сирі дані та обмеження висновку.

**Архітектура:** взяти `dot_bench.rs` і `machine_math_skylake.S` з окремого зафіксованого upstream-коміту `33f0c4d1ea812a09dd121bd15ed741241d5dbc65`; не змінювати pinned `external/sens@1f1bf676eeac605e065035d9dd2adaae807f1788`. Thin Rust worker викликає існуючі ABI-символи окремими процесами; Python вимірювач повторно використовує RAPL primitives з `scripts/energy/measure.py`, запускає випадково перемішані парні блоки й зберігає лише чесні package-level дані.

**Стек:** Rust/Cargo, GNU assembler/compiler, Python 3, Linux powercap RAPL, існуючі RAPL `Zone`/`Sampler` механізми.

**Специфікація:** GitHub issue #598 у репозиторії `juv4uk/wsm-lazarus`.

## Обмеження

- RAPL `package` — енергія всього CPU-пакета, не окремого процесу.
- Ядра SSE2 та AVX2/FMA беруться з одного зафіксованого upstream source SHA.
- Перевіряти CPU AVX2/FMA до першого виклику AVX2; інакше припинятися без виміру.
- Спочатку перевірити арифметичний результат `dot_bench` і окремих workers.
- Виконати 30 перемішаних парних блоків та окремий idle-контроль; зберегти raw RAPL readings і метадані середовища.
- Hosted CI перевіряє збірку, коректність і негативні механічні випадки; вона не оголошує апаратні джоулі.
- Не стверджувати перевагу, якщо різниця не відокремлюється від idle/фонової варіації.

## Файлова структура

- `scripts/energy/machine-math-worker.rs` — мінімальний окремий прямий виклик одного ABI kernel з тими самими векторами, що й upstream benchmark.
- `scripts/energy/machine_math_rapl.py` — перевірка source SHA/ISA, збірка, паритет, randomized sampling, summary та no-clobber JSON.
- `scripts/energy/test-machine-math-rapl.py` — unit/negative тести parser, paired statistics, wrap і fail-closed поведінки.
- `.github/workflows/energy-baseline.yml` — запускає механічні перевірки; CI не заявляє фізичне вимірювання.
- `benchmarks/energy-machine-math-20261030/README.uk.md` — метод, host, результати й обмеження.
- `benchmarks/energy-machine-math-20261030/results.json` — summary та повні host/compiler/source metadata.
- `benchmarks/energy-machine-math-20261030/samples.jsonl` — сирі package-zone читання для усіх запусків.

## План перевірок

1. Спочатку додати тести та зафіксувати їхній RED на відсутніх функціях; потім реалізувати вимірювач.
2. Побудувати upstream `dot_bench` та обидва thin workers із однакових pinned assembler bytes; звірити результати в межах upstream допуску.
3. Запустити RAPL preflight і 30 randomized paired blocks із прив'язкою до CPU 2; окремо записати idle інтервали.
4. Перевірити JSON no-clobber, SHA, валідність усіх сирих зон, інтервали, CPU/ISA та відсутність заяв per-process energy.
5. Запустити Python механічні тести й повний `scripts/test.sh`; перевірити `git diff --check` та CI на точному main SHA.
