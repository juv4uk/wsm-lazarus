# Вимірювання циклу зміни FPC (W1/W2)

**Статус:** реалізовано контракт runner-а; реальних 20+20 серій і чисел ще немає. Справжню серію з холодним page cache позначено недоступною: повний preflight читає та збирає джерела, а runner не скидає кеш і не перезавантажує ОС. Цей документ не містить вигаданих чисел.

**Задача:** [#1089](https://github.com/juv4uk/wsm-lazarus/issues/1089). Методологічна основа — [час ітерації](chas-iteratsii.uk.md), а не старі енергетичні серії виконання.

## Межа вимірювання

Один вимірюваний цикл — **bash scripts/build.sh**: повне headless-збирання src/wsm.headless.lpr з параметрами **-B -Mobjfpc -O1**, компіляція та запуск test-envframe, а також scripts/test-nativeeval.sh. Перед серіями один раз виконується повний **bash scripts/test.sh**; його тривалість і журнали зберігаються окремо й не додаються до вимірюваної ітерації.

Вимірюється time.perf_counter_ns() навколо процесу scripts/build.sh, включно зі стартом процесу, FPC-збиранням і вбудованими перевірками. Не вимірюються час людського мислення, редагування, інсталяція компілятора чи підготовка pinned authority.

## Серії та кеш

Після повного scripts/test.sh preflight page cache вже прогрітий. Тому runner не називає свої серії cold/warm page-cache вимірами:

- **after_preflight_no_extra_warmup:** 20+ циклів після preflight, без додаткового benchmark warmup. Кожен build.sh видаляє build/m0.2 і робить повне -B збирання.
- **after_one_extra_discarded_build:** один успішний, не врахований у статистиці build.sh прогрів, потім 20+ вимірюваних циклів. Build output також очищується, компіляція лишається повною.

**Справжня холодна серія недоступна:** runner не скидає Linux page cache, не перезавантажує систему й не змінює governor, Turbo чи affinity. У звіті true_cold_cache_series.status=UNAVAILABLE; не інтерпретуйте першу серію як cold cache.

## Toolchain matrix

| Лінія | Умова допуску | Роль |
|---|---|---|
| FPC 3.2.2 | exact fpc -iV, Linux x86_64; окремий --rtl-id | чинна контрольна база; старі докази не переписуються |
| FPC 3.2.4 | exact fpc -iV і source revision 66940ee65006538dba16b4c584d3cfb1cc08985e | кандидат; джерельний revision має бути зібраний окремо |
| FPC 3.3.1 x86_64-embedded | відхиляється цим runner-ом | окремий embedded/UEFI напрям wsm-os-lisp#113, не host-Linux benchmark |

Параметр --rtl-id є обов'язковим: версія компілятора сама по собі не визначає встановлений RTL. Runner зберігає SHA256 виконуваного компілятора, source revision (коли відомий), target CPU/OS, host, governor/Turbo, affinity, flags/команди, git SHA та всі raw durations. Для 3.2.4 приймається лише вказаний upstream source SHA.

**Межа source provenance:** --source-revision — задекларований оператором SHA з exact-match перевіркою, а не підписана атестація побудови компілятора з цього дерева. Runner прив'язує звіт до SHA256 фактичного fpc, але не доводить сам зв'язок між source tree і binary. Для повного доказу 3.2.4 поряд зі звітом потрібно зберегти окремий source-build transcript/manifest із командою складання, SHA дерева, ідентичністю RTL та SHA виконуваного файла. Без цього 3.2.4 лишається candidate-профілем, а не новою baseline.

Офіційна сторінка Free Pascal усе ще називає 3.2.2 останнім ready-made release; development snapshots 3.3.x позначені як непідтримувані. Це не заперечує окремої source-tag лінії 3.2.4, але пакетний статус і source revision не можна змішувати. [Офіційні завантаження](https://www.freepascal.org/download.html) · [development snapshots](https://www.freepascal.org/develop.html).

Розглянуто Hyperfine: він підтримує warmup, статистику, JSON і налаштовувану підготовку кешу. Основний runner використовує Python stdlib, щоб не додавати залежність і не виконувати довільний shell command: команди фіксовані — scripts/test.sh і scripts/build.sh. Hyperfine можна застосувати як окрему незалежну перевірку; його числа не змішувати з цим звітом. [Hyperfine manual](https://man.archlinux.org/man/hyperfine.1.en).

## Запуск

Після встановлення потрібного host compiler та матеріалізації чинного external/sens:

~~~bash
# Контрольна база — FPC 3.2.2
python3 scripts/iteration/measure.py \
  --fpc /абсолютний/шлях/до/fpc-3.2.2 \
  --expected-version 3.2.2 \
  --toolchain-id fpc-3.2.2-installed \
  --rtl-id fpc-rtl-3.2.2-installed \
  --repetitions 20 \
  --output-dir evidence/iteration/fpc-3.2.2

# Кандидат — source-built FPC 3.2.4 з pinned upstream revision
python3 scripts/iteration/measure.py \
  --fpc /абсолютний/шлях/до/fpc-3.2.4 \
  --expected-version 3.2.4 \
  --toolchain-id fpc-3.2.4-source-66940ee \
  --rtl-id fpc-rtl-3.2.4@66940ee65006538dba16b4c584d3cfb1cc08985e \
  --source-revision 66940ee65006538dba16b4c584d3cfb1cc08985e \
  --repetitions 20 \
  --output-dir evidence/iteration/fpc-3.2.4
~~~

Результат кожного запуску — report.json та окремі stdout/stderr для preflight, warmup і кожного зразка. Вихідна директорія мусить бути новою; існуючі результати не перезаписуються. Якщо команда падає або перевищує timeout, runner не створює звіт PASS, а лишає FAILED.txt і вже записані журнали.

## Енергія

Runner повторно використовує scripts/energy/measure.py для виявлення й читання RAPL package-зон та обробки обертання лічильника. Якщо зона відсутня, недоступна або інтервал надто довгий для безпечного визначення дельти, значення не замінюється нулем: у звіті буде ENERGY_NOT_MEASURED або PACKAGE_BOUNDARY_PARTIALLY_MEASURED.

Package RAPL включає фонове навантаження всього CPU package. Це **не** джоулі процесу FPC. Не віднімати простій і не подавати різницю як енергію компілятора без окремого експерименту з обґрунтованою межею системи.

## Перевірки й межі доказу

- python3 -m unittest discover -s scripts/iteration -p 'test_*.py' -v перевіряє квантили, мінімум повторів, exact version/source pin, відмову від embedded target, RAPL wrap/gap та незатирання журналів.
- .github/workflows/iteration-measure.yml запускає лише контрактні тести; CI runner не видається за часовий чи енергетичний замір на машині власника.
- scripts/test.sh є обов'язковим preflight кожного реального вимірювання.
- 3.2.4 не стає новою baseline, доки не буде окремо виконано всі 20+20 серій, перевірено той самий headless preflight, збережено source-build provenance та порівняно поведінку й помилки. 3.3.1 embedded не входить до цього порівняння.

## Представлення й час життя даних

FPC — окремий виконуваний файл; --fpc вказує його абсолютний шлях, а runner передає той самий шлях через FPC і початок PATH дочірнім процесам. stdout/stderr дочірнього процесу зберігаються як сирі байти у власних log-файлах; JSON містить їхні SHA256 та розміри, а не перетворює байти на семантичні значення. Час — 64-бітний монотонний лічильник наносекунд Python; він не залежить від системного календаря. Буфери звільняються після кожного subprocess.run, журнали належать каталогу --output-dir і не видаляються runner-ом.

Питання для перевірки розуміння: чому час вимірюється навколо build.sh, а не fpc -iV? Чому -B лишається в обох серіях? Чому package RAPL не є енергією процесу? Чому embedded 3.3.1 не можна включити до host-Linux квантилів?
