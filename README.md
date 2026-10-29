# wsm-lazarus — нативна система SENS на Free Pascal

Мета — побудувати нативну систему реалізації SENS на Free Pascal/Lazarus за класом компонентів подібну до SBCL: виконання, REPL, завантаження Core4, компіляція, діагностика, керування пам'яттю та образи. Це **не** реалізація Common Lisp.

## Мовний авторитет

Мовні закони визначає тільки pinned [репозиторій SENS](external/sens) (gitlink `1f1bf676eeac605e065035d9dd2adaae807f1788`, Contract 12.0). Канонічна машинна мова — точні двійкові слова з доменом, шириною, бітами та ратифікованим законом. `.sens` несе фізичні паковані слова; українська `ук` і текстові `.lisp` є людськими проєкціями. Назва або текстова проєкція не створює семантики й не замінює двійковий свідок.

Contract 12.0 забороняє активні SID8/Sens8/Function8 маршрути. Наявність історичних файлів не означає, що їх дозволено включати до нового виконання; технічну міграцію не оголошено завершеною.

## Що вже фізично реалізовано

Таблицю звірено з `main@07b4a6b87eb8309d12858ada87a68710ec8d6e46` (30.10.2026) і наявними перевірками. Це опис перевірених зрізів, а не заява про повну реалізацію мови.

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
| Виконання та вибіркова AOT-компіляція Core1 | [`src/wsm.core1selektor.pas`](src/wsm.core1selektor.pas), [`src/senscore1selektor.lpr`](src/senscore1selektor.lpr), [census допуску](scripts/test-core1-census.sh), [AOT додавання](scripts/test-lowerpinnedcore1add.sh), [AOT множення](scripts/test-lowerpinnedcore1mul.sh) | Відбірник приймає **94 із 96** фізичних визначень pinned `core1.sens`; окремі перевірені фізичні визначення додавання й множення проходять до ELF64. Існують конкретні виконувані приклади для селекторів D3/D4/D5/D6, рекурсії, арифметики та інших форм. | Відхилені `ядро1-застосувати` і `ядро1-обчислити`; admission не доводить виконання всіх 94 тіл. Немає повного Core1, GC-інтеграції чи загального компілювання бібліотеки. |
| Проміжні подання та нативна AOT-компіляція | [`src/wsm.compiler.pas`](src/wsm.compiler.pas), [`src/wsm.exactir.pas`](src/wsm.exactir.pas), спільний [`src/wsm.wideir.pas`](src/wsm.wideir.pas), [`src/senschyslo.lpr`](src/senschyslo.lpr), [фізичний D5→WideIR→ELF тест](scripts/test-irwidefront-chastka.sh), [AOT тіла з фізичного `.sens`](src/sensbodyfileelf.lpr), [перевірка тіла](scripts/test-bodyfile-compiler.sh), [CI AOT тіла](.github/workflows/bodyfile-compiler.yml), [незалежний SENS-допуск](scripts/sens-oracle-first-elf.sh), [повний запис T5M і ELF](src/senswidezakhystzahalelf.lpr), [16 фізичних записів та oracle](scripts/test-wideguard-front.sh), [CI запису](.github/workflows/wideguard-front.yml), [архівний опис LCL workflow](staged-out/workflows/lazarus-sens-ide-compiler.yml) | Є кілька реальних, окремо перевірених шляхів до ELF64: 107 вкладених D5 програм; 16 фізичних програм із двома окремими Core1 `CALL/RET`; точковий D5 `більше?` через signed `CMP/SETG`; файловий AOT фізичного тіла з одним/двома exact D7-параметрами, D24-аргументами та опційним self-key. Окремий CLI захищає повний фізичний T5M-запис і атомарну публікацію ELF для чотирьох перевірених профілів D5/D6: 16 запусків ELF зі збігом вихідних байтів і pinned SENS oracle, 24 негативи, 16 відмов ENOSPC через `/dev/full`. | Це реальний, але **профільний** компілятор: корпус точних фізичних форм і негативів розширюється, а непідтримані форми відхиляються. `SIR1` та `ExactIR` самі не є backend-ом; D7/D24 аргументи файлового AOT задаються під час компіляції, тому цей зріз не доводить загальний runtime ABI, довільну компіляцію, повний оптимізатор або компіляцію всього Core1/Core4. |
| Змішані фізичні дерева D5 | [`src/sensarithderevoelf.lpr`](src/sensarithderevoelf.lpr), [`src/wsm.irarithderevo.pas`](src/wsm.irarithderevo.pas), [перевірка](scripts/test-irarithderevo.sh), [FPC/SENS workflow](.github/workflows/ir-arithderevo.yml) | Canonical T5M проходить pinned WideIR і exact D5:01010/01011 binding; кожен проміжний результат перевіряється як D12, а непідтримана D24 promotion відхиляється. Існує машинне збереження лівого піддерева через `PUSH/POP` та перевірений порядок `ADD/SUB`. | 32 різні дерева з 1–31 операцією → 32 ELF64 PIE, 32/32 фізичних T5M результатів підтверджені pinned SENS 12.0; перевірено 17+2 негативи. Межа: лише ці два D5 закони й дерева до 31 операції; немає загального компілятора або енергетичного виміру. |
| Lazarus IDE | [Пакунок `ide/sens_ide_map.lpk`](ide/sens_ide_map.lpk), [українська інструкція](ide/README.uk.md), [GTK2/Xvfb gate](scripts/test-sens-ide-compile.sh), [архівний YAML опис workflow](staged-out/workflows/lazarus-sens-ide-compiler.yml) | IDE-пакунок має команди мапи та компіляції фізичного `.sens` через спільний WideIR; форма може виконати лише щойно перевірений ELF64 і показати точні T5M байти/біти. Раніше GTK2/Xvfb gate збирав design-time IDEIntf/LCL, але його workflow тепер збережено поза активним `.github/workflows`. | Цей історичний автоматизований тест не доводить ручну інсталяцію пакунка в повну Lazarus IDE. Це не GUI-runtime і не дозвіл запускати довільний ELF чи довільну SENS-програму. |
| Енергетичні виміри | [RAPL-порівняння 16 готових ELF](evidence/energy-four-elf-20261029/README.uk.md), [D24 native-loop матриця](evidence/energy-native-d12-loop-20261029/README.uk.md), [порівняння Core1/SENS REPL](docs/energy-repl-core1.uk.md), [Fibonacci-протокол](benchmarks/cross-language/fib/energy-cross.uk.md), [машинна математика SSE2/AVX2](benchmarks/energy-machine-math-20261030/README.uk.md) | Є реальні локальні RAPL спостереження для конкретних готових ELF і вузьких ядер; окремі протоколи перевіряють той самий результат, сирі пакетні лічильники й відтворюваність. | Це не енергія окремого процесу і не рейтинг мов. Чотири D3 форми, одна D24-сума, окрема REPL-форма та SSE2/AVX2 dot-product не доводять загальну енергоефективність мови SENS. Новий файловий AOT Core1 ще не виміряно; його D24 значення задаються під час компіляції. Hosted CI перевіряє механіку, фізичні джоулі там не вимірюються. |
| GC, діагностика та знімок фрейму | [`src/wsm.gc.pas`](src/wsm.gc.pas), [`src/wsm.debugtrace.pas`](src/wsm.debugtrace.pas), [`src/wsm.faulttrace.pas`](src/wsm.faulttrace.pas), [`src/wsm.uktrace.pas`](src/wsm.uktrace.pas), [`src/wsm.image.pas`](src/wsm.image.pas), [`scripts/test-uktrace.pas`](scripts/test-uktrace.pas) | Є українська проєкція точних кадрів і знімка помилки; це перевірені механізми, не інтегрований runtime GC і не повний образ системи. |

Загальний стан, відкриті залежності та незавершені вертикалі ведуться в [дорожній карті](docs/native-system-roadmap.uk.md) та задачах [#41](https://github.com/juv4uk/wsm-lazarus/issues/41) — [#48](https://github.com/juv4uk/wsm-lazarus/issues/48). Є вузькі фізичний `.sens`/T5M та український `ук` входи. Нативний backend уже породжує ELF64 для перевірених профілів, але не компілює довільну SENS-програму. Перший Core4 binary slice доводить лише конкретне одноаргументне замикання та атомні глобали. Повний Core4, повний REPL і загальний семантичний паритет не доведені.

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
