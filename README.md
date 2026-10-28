# wsm-lazarus — нативна система SENS на Free Pascal

Мета — побудувати нативну систему реалізації SENS на Free Pascal/Lazarus за класом компонентів подібну до SBCL: виконання, REPL, завантаження Core4, компіляція, діагностика, керування пам'яттю та образи. Це **не** реалізація Common Lisp.

## Мовний авторитет

Мовні закони визначає тільки pinned [репозиторій SENS](external/sens) (gitlink `1f1bf676eeac605e065035d9dd2adaae807f1788`, Contract 12.0). Канонічна машинна мова — точні двійкові слова з доменом, шириною, бітами та ратифікованим законом. `.sens` несе фізичні паковані слова; українська `ук` і текстові `.lisp` є людськими проєкціями. Назва або текстова проєкція не створює семантики й не замінює двійковий свідок.

Contract 12.0 забороняє активні SID8/Sens8/Function8 маршрути. Наявність історичних файлів не означає, що їх дозволено включати до нового виконання; технічну міграцію не оголошено завершеною.

## Що вже фізично реалізовано

Таблицю перевірено на `main@11a66e53129d84e7f2d8d269e9670583e3e4435d` (28.10.2026); перед посиланням на цей стан звіряй новіші злиття та їхній CI.

| Частина | Доказ у репозиторії | Межа доказу |
|---|---|---|
| FPC headless build і CI | [`scripts/test.sh`](scripts/test.sh), [fpc-headless workflow](.github/workflows/fpc-headless.yml) | Збірка й механічні тести, не загальний семантичний паритет. |
| T5M фізичні байти та CLI | [`src/wsm.t5m.pas`](src/wsm.t5m.pas), [`src/wsm.t5madmission.pas`](src/wsm.t5madmission.pas), [`src/senst5m.lpr`](src/senst5m.lpr), [`scripts/test-t5m-cli.sh`](scripts/test-t5m-cli.sh), [`scripts/test-t5madmission.sh`](scripts/test-t5madmission.sh) | Обмежений потоковий допуск, транспорт, читабельний перегляд і D2-структурна перевірка; не саме виконання. |
| D2 AST та фізичні позиції | [`src/wsm.d2source.pas`](src/wsm.d2source.pas), [`src/wsm.physloc.pas`](src/wsm.physloc.pas), [`scripts/test-d2source.sh`](scripts/test-d2source.sh), [`scripts/test-physloc.sh`](scripts/test-physloc.sh) | Структура й точні фізичні інтервали слова/байта/трита, не семантичне тлумачення. |
| Доменні координати | [`src/wsm.domain.pas`](src/wsm.domain.pas), [`src/wsm.bind.pas`](src/wsm.bind.pas), [`src/wsm.binarybind.pas`](src/wsm.binarybind.pas), [`src/wsm.binarylocbind.pas`](src/wsm.binarylocbind.pas), [`src/wsm.binarytree.pas`](src/wsm.binarytree.pas), [`src/sensbinary.lpr`](src/sensbinary.lpr) | Exact-domain зіставлення, фізичне дерево AST та CLI-огляд; сама координата не доводить викличність. |
| Виконання D3 | [`src/wsm.nativeeval.pas`](src/wsm.nativeeval.pas), [`src/wsm.binaryexec.pas`](src/wsm.binaryexec.pas), [`src/sensvykon.lpr`](src/sensvykon.lpr), [`scripts/test-binaryexec.sh`](scripts/test-binaryexec.sh), [фізичні T5M-свідки](evidence/nativeeval-g3-2/README.uk.md) | Вузькі точні D1/D3-форми фізичного `.sens` проходять T5M/D2 до наявного evaluator. Це не загальне виконання програм і не загальний `.sens`↔`.lisp` перетворювач. |
| Явний CLI української проєкції | [`src/sens_uk_d3.lpr`](src/sens_uk_d3.lpr), [`scripts/test-sens-uk-d3.sh`](scripts/test-sens-uk-d3.sh), [ізольований FPC workflow](.github/workflows/native-uk-d3-cli.yml) | Окремий режим виконує вузькі D3-форми з явно заданої `ук`-проєкції; це не oracle і не приймач фізичного `.sens`. |
| Середовище й сесійні механізми | [`src/wsm.envframe.pas`](src/wsm.envframe.pas), [`src/wsm.session.pas`](src/wsm.session.pas), [`src/wsm.sessiond3.pas`](src/wsm.sessiond3.pas), [`src/wsm.lineinput.pas`](src/wsm.lineinput.pas), [`src/wsm.sessionwire.pas`](src/wsm.sessionwire.pas) | Є виконання підтриманих D3-форм у багатоформовій сесії; фрейми, багаторядковий ввід і приватний пакетний транспорт мають власні межі. Це ще не повний SENS REPL. |
| Core4 джерело й перше виконання | [`src/wsm.core4source.pas`](src/wsm.core4source.pas), [`src/wsm.core4slice.pas`](src/wsm.core4slice.pas), [`src/wsm.core4runtime.pas`](src/wsm.core4runtime.pas), [перевірка виконання](scripts/test-core4runtime.sh), [FPC workflow](.github/workflows/core4-runtime.yml) | Loader бере перші три визначення з canonical pinned `core4.sens`: D4 DEFINE/LAMBDA замикання і два точні D24-атоми. Ім’я/параметр зв’язуються за exact D7-послідовністю; повторні виклики повертають незмінний атомний аргумент, а глобальні імена — завантажене exact-значення. Числової арифметики цей зріз не виконує. Це не загальний evaluator Core4, не довільні тіла/структури та не виконання `.lisp` як канонічного джерела. |
| Проміжні подання | [`src/wsm.compiler.pas`](src/wsm.compiler.pas), [`src/sensc.lpr`](src/sensc.lpr), [`src/wsm.exactir.pas`](src/wsm.exactir.pas), [`scripts/test-compiler.sh`](scripts/test-compiler.sh), [`scripts/test-exactir.sh`](scripts/test-exactir.sh) | SIR1 структурно перевіряється; ExactIR зберігає точні доменні двійкові координати. Жодне з подань ще не є виконуваним компілятором або native backend. |
| GC, діагностика та знімок фрейму | [`src/wsm.gc.pas`](src/wsm.gc.pas), [`src/wsm.debugtrace.pas`](src/wsm.debugtrace.pas), [`src/wsm.faulttrace.pas`](src/wsm.faulttrace.pas), [`src/wsm.uktrace.pas`](src/wsm.uktrace.pas), [`src/wsm.image.pas`](src/wsm.image.pas), [`scripts/test-uktrace.pas`](scripts/test-uktrace.pas) | Є українська проєкція точних кадрів і знімка помилки; це перевірені механізми, не інтегрований runtime GC і не повний образ системи. |

Загальний стан, відкриті залежності та незавершені вертикалі ведуться в [дорожній карті](docs/native-system-roadmap.uk.md) та задачах [#41](https://github.com/juv4uk/wsm-lazarus/issues/41) — [#48](https://github.com/juv4uk/wsm-lazarus/issues/48). Є два явні вузькі входи: фізичний `.sens`/T5M та українська `ук`-проєкція. Перший Core4 binary slice доводить лише один повторний одноаргументний виклик; жоден наявний вхід не означає повний інтерактивний REPL, загальне виконання Core4 чи native codegen.

## Мінімальні перевірки

Потрібен Free Pascal 3.2.x і матеріалізований pinned authority slice:

```sh
./scripts/sync-authority.sh
./scripts/test.sh
```

Окремо зібрати та перевірити інструмент структурного допуску pinned Core4:

```sh
./scripts/test-core4-cli.sh
./build/m0.2/bin/senscore4 --check .
```

Вузький реальний виклик першого визначення з canonical Core4 `.sens`:

```sh
./scripts/test-core4runtime.sh
```

Тест доводить завантаження трьох початкових pinned визначень: першого
D4 DEFINE/LAMBDA і двох D24-атомів; exact D7-зв'язування; два послідовні
виклики замикання з D1/D24 та читання обох D24-глобалів. D24 значення
переносяться непрозоро — це не арифметика. Це не означає, що всі Core4-форми
або REPL підтримуються.

`.sir` — внутрішній структурний формат. Він не є канонічним `.sens`, виконуваною програмою або доказом семантичної відповідності.

## Принцип

**SENS задає закони; Free Pascal/Lazarus реалізує механізми.** Нові людські поняття, задачі, коміти, пояснення й документацію формулюй українською. Дивись [правила агентів](AGENTS.md) та [архітектурну дорожню карту](docs/native-system-roadmap.uk.md).

## Ліцензія

ВОЛЬНІСТЬ (див. [`LICENSE`](LICENSE)).
