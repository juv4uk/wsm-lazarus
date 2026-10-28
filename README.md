# wsm-lazarus — нативна система SENS на Free Pascal

Мета — побудувати нативну систему реалізації SENS на Free Pascal/Lazarus за класом компонентів подібну до SBCL: виконання, REPL, завантаження Core4, компіляція, діагностика, керування пам'яттю та образи. Це **не** реалізація Common Lisp.

## Мовний авторитет

Мовні закони визначає тільки pinned [репозиторій SENS](external/sens) (gitlink `1f1bf676eeac605e065035d9dd2adaae807f1788`, Contract 12.0). Канонічна машинна мова — точні двійкові слова з доменом, шириною, бітами та ратифікованим законом. `.sens` несе фізичні паковані слова; українська `ук` і текстові `.lisp` є людськими проєкціями. Назва або текстова проєкція не створює семантики й не замінює двійковий свідок.

Contract 12.0 забороняє активні SID8/Sens8/Function8 маршрути. Наявність історичних файлів не означає, що їх дозволено включати до нового виконання; технічну міграцію не оголошено завершеною.

## Що вже фізично реалізовано

Таблицю перевірено на `main@9811086305fc066a2f48641e3a5dec6e724bf65d` (28.10.2026); перед посиланням на цей стан звіряй новіші злиття та їхній CI.

| Частина | Доказ у репозиторії | Межа доказу |
|---|---|---|
| FPC headless build і CI | [`scripts/test.sh`](scripts/test.sh), [fpc-headless workflow](.github/workflows/fpc-headless.yml) | Збірка й механічні тести, не загальний семантичний паритет. |
| T5M фізичні байти та CLI | [`src/wsm.t5m.pas`](src/wsm.t5m.pas), [`src/senst5m.lpr`](src/senst5m.lpr), [`scripts/test-t5m-cli.sh`](scripts/test-t5m-cli.sh) | Транспорт, читабельний перегляд і D2-структурна перевірка; не виконання. |
| D2 AST та фізичні позиції | [`src/wsm.d2source.pas`](src/wsm.d2source.pas), [`src/wsm.physloc.pas`](src/wsm.physloc.pas), [`scripts/test-d2source.sh`](scripts/test-d2source.sh), [`scripts/test-physloc.sh`](scripts/test-physloc.sh) | Структура й точні фізичні інтервали слова/байта/трита, не семантичне тлумачення. |
| Доменні координати | [`src/wsm.domain.pas`](src/wsm.domain.pas), [`src/wsm.bind.pas`](src/wsm.bind.pas), [`src/wsm.binarybind.pas`](src/wsm.binarybind.pas), [`src/wsm.binarylocbind.pas`](src/wsm.binarylocbind.pas), [`src/sensbinary.lpr`](src/sensbinary.lpr) | Exact-domain зіставлення й фізичний CLI-огляд; сама координата не доводить викличність. |
| Виконання D3 | [`src/wsm.nativeeval.pas`](src/wsm.nativeeval.pas), [`scripts/test-nativeeval.pas`](scripts/test-nativeeval.pas), [фізичні T5M-свідки](evidence/nativeeval-g3-2/README.uk.md) | Обмежені D3-форми, exact-domain dispatch і обмежена арена; це не повний runtime і не загальний бінарний ingress. |
| Середовище й сесійні механізми | [`src/wsm.envframe.pas`](src/wsm.envframe.pas), [`src/wsm.session.pas`](src/wsm.session.pas), [`src/wsm.lineinput.pas`](src/wsm.lineinput.pas), [`src/wsm.sessionwire.pas`](src/wsm.sessionwire.pas) | Фрейми, багаторядковий ввід, приватний пакетний транспорт з обмеженою чергою; самі по собі не утворюють повний SENS REPL. |
| Core4 source admission | [`src/wsm.core4source.pas`](src/wsm.core4source.pas), [`src/senscore4.lpr`](src/senscore4.lpr), [окремий FPC workflow](.github/workflows/core4-source-admission.yml) | Перевірка pinned джерела й структурного SIR1; **не** виконання Core4. |
| Структурний SIR1 | [`src/wsm.compiler.pas`](src/wsm.compiler.pas), [`src/sensc.lpr`](src/sensc.lpr), [`scripts/test-compiler.sh`](scripts/test-compiler.sh) | Верифікація/огляд приватного IR; це не машинний код і не виконуваний компілятор. |
| GC, діагностика та знімок фрейму | [`src/wsm.gc.pas`](src/wsm.gc.pas), [`src/wsm.debugtrace.pas`](src/wsm.debugtrace.pas), [`src/wsm.faulttrace.pas`](src/wsm.faulttrace.pas), [`src/wsm.image.pas`](src/wsm.image.pas) | Перевірені механізми пам'яті, стеку та обмеженого знімка фрейму; не інтегрований runtime GC і не повний образ системи. |

Загальний стан, відкриті залежності та незавершені вертикалі ведуться в [дорожній карті](docs/native-system-roadmap.uk.md) та задачах [#41](https://github.com/juv4uk/wsm-lazarus/issues/41) — [#48](https://github.com/juv4uk/wsm-lazarus/issues/48). Наприклад, фізичний місток `.sens` до обмеженого виконавця, повний інтерактивний REPL, фактичне виконання Core4 і native codegen ще не підтверджені як готові.

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

`.sir` — внутрішній структурний формат. Він не є канонічним `.sens`, виконуваною програмою або доказом семантичної відповідності.

## Принцип

**SENS задає закони; Free Pascal/Lazarus реалізує механізми.** Нові людські поняття, задачі, коміти, пояснення й документацію формулюй українською. Дивись [правила агентів](AGENTS.md) та [архітектурну дорожню карту](docs/native-system-roadmap.uk.md).

## Ліцензія

ВОЛЬНІСТЬ (див. [`LICENSE`](LICENSE)).
