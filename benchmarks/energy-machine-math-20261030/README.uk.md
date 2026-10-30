# Пакетна енергія ядер машинної математики SENS

Це локальний дослід на Intel Core i5-6400: однаковий dot-product виконується двома наявними асемблерними шляхами SENS — послідовним scalar SSE2 `sens_dot_scalar` та векторним AVX2/FMA `sens_dot_avx2`. Це порівняння двох машинних ядер, **не мов і не повного компілятора SENS**.

## Вимір

30 рандомізованих парних блоків із seed `598`. У кожному блоці в випадковому порядку запускався окремим процесом кожен kernel та контроль `/bin/true`; worker закріплено за CPU 2 через `taskset`. Для кожного kernel: `n=65 536`, 4096 викликів і один попередній виклик-прогрів. Обидва ядра отримали ті самі детерміновані вектори та повернули однакову суму `532 698 350 592`.

| Умова | Медіана пакетної енергії за інтервал | Медіана тривалості RAPL-інтервалу |
| --- | ---: | ---: |
| Scalar SSE2 | 9,859 Дж | 370,09 мс |
| AVX2/FMA | 2,610 Дж | 99,61 мс |
| `/bin/true` контроль | 0,102 Дж | 4,37 мс |

Парна різниця AVX2/FMA мінус SSE2 становила **−7,138 Дж** (95% bootstrap CI −7,427…−6,430 Дж). Медіанне скорочення пакетного приросту в парних блоках — **72,89%** (95% bootstrap CI 72,26…73,76%). Інтервали — percentile bootstrap, по 20 000 повторних вибірок; для енергії seed `598`, для часу `599`, для відсотка `600`. Відношення медіан тривалості — приблизно 3,72× на користь AVX2/FMA. Інтервал тривалості AVX2/FMA мінус SSE2: −270,69 мс (95% bootstrap CI −271,80…−269,08 мс).

У цьому конкретному навантаженні різниця між двома kernel-інтервалами відокремилася від нуля. Це **не означає**, що повна різниця пакетної енергії належить worker-процесу: Intel RAPL вимірює пакет CPU, куди входять ОС, робочий стіл та фонові процеси. `/bin/true` є лише коротким контролем запуску процесу; його енергію не віднімали від результатів. Кожен RAPL-інтервал включає створення процесу, виділення й заповнення векторів, прогрів і всі повторні виклики, а не лише інструкції ядра.

Зони `package-0`, `core` і `dram` зберігаються окремо в сирих даних. У підсумку використано лише `package-0`; зони не складали, бо `core` вкладена в пакет. Це апаратний профіль двох реалізацій однакової операції на одному процесорі, а не рейтинг мов і не загальний висновок про енергоефективність SENS.

## Залізо та джерела

- CPU: Intel Core i5-6400, AVX2 та FMA підтверджені CPUID.
- Ubuntu kernel `7.0.0-42-generic`; governor `powersave`, Turbo дозволений (`no_turbo=0`); CPU affinity — ядро 2.
- Навантаження хоста перед серією: load average `2.96 2.93 2.00`; RAPL читався з трьома зонами.
- GCC `13.3.0`, Rust/Cargo `1.99.0`, Zig `0.16.0`.
- Бенчмарк та worker зафіксовані в `juv4uk/sens@33f0c4d1ea812a09dd121bd15ed741241d5dbc65`; SHA асемблера, upstream `dot_bench.rs` і worker наведені в JSON.
- Код вимірювача: `juv4uk/wsm-lazarus@517050c61761ec2699b3f0fdac03360bff8d7b44`; його робоче дерево було чистим. Мовний authority підмодуля не змінювався: `external/sens@1f1bf676eeac605e065035d9dd2adaae807f1788` (Contract 12.0).

Повний підсумок, параметри, SHA артефактів та всі парні значення: [`results.json`](results.json). Дев'яносто запусків та повні часові читання трьох зон RAPL: [`samples.jsonl`](samples.jsonl).

## Відтворення

Потрібні Linux x86-64 з AVX2/FMA та Intel RAPL, GCC, Rust/Cargo 1.99.0 і Zig 0.16.0. Для вимірювання root потрібен лише для читання sysfs RAPL; окремі workers запускаються від звичайного користувача. Скрипт відмовляється перезаписувати результати й перевіряє обидві суми перед серією.

Спочатку створити окрему чисту копію коду стенду за SHA, вказаним у JSON, та окреме дерево upstream SENS:

```sh
git worktree add --detach /tmp/wsm-machine-math 517050c61761ec2699b3f0fdac03360bff8d7b44
git -C /tmp/wsm-machine-math submodule update --init external/sens
git clone https://github.com/juv4uk/sens.git /tmp/sens-machine-math
git -C /tmp/sens-machine-math checkout --detach 33f0c4d1ea812a09dd121bd15ed741241d5dbc65
export PATH="/path/to/zig-0.16.0:$PATH"
```

Спершу перевірити збірку та числовий паритет без читання або заяви про енергію:

```sh
timeout 900s python3 /tmp/wsm-machine-math/scripts/energy/machine_math_rapl.py \
  --root /tmp/wsm-machine-math --sens-source /tmp/sens-machine-math \
  --results /tmp/check-results.json --samples /tmp/check-samples.jsonl --check-only
```

Для нового апаратного прогону задати нову директорію призначення:

```sh
sudo -E env PATH="$PATH" python3 /tmp/wsm-machine-math/scripts/energy/machine_math_rapl.py \
  --root /tmp/wsm-machine-math --sens-source /tmp/sens-machine-math \
  --results /tmp/new-run/results.json --samples /tmp/new-run/samples.jsonl \
  --rounds 30 --n 65536 --repetitions 4096 --core 2 --seed 598
```

GitHub Actions перевіряє механічні інваріанти й FPC energy harness, але hosted CI не читає фізичні джоулі. У CI `ENERGY_NOT_MEASURED` залишається буквальним статусом.
