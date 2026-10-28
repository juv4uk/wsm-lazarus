# Нативна система SENS на Free Pascal — дорожня карта

Ціль — повноцінна нативна система реалізації SENS за класом компонентів подібна до SBCL: виконання, REPL, бібліотечний loader, компілятор, нативний backend, керування пам'яттю, діагностика та системні образи. Подібність стосується складу інженерних компонентів, **не** семантики Common Lisp.

## Мовний контракт

Єдине джерело мовних законів — pinned `juv4uk/sens`, зараз gitlink `external/sens@1f1bf676eeac605e065035d9dd2adaae807f1788`; чинний контракт цього pin — ратифікований власником SENS 12.0 у `external/sens/contracts/language-contract-12.lisp`.

Канонічна машинна мова SENS складається з точних двійкових слів, кожне з яких тлумачиться в точному домені за відповідним ратифікованим законом. Зберігай ширину, біти, домен і походження. `.sens` несе фізичні паковані слова. `ук` та інші поверхні, включно з людськими `.lisp`, є проєкціями: вони допомагають людині вводити або читати програму, але не є семантичним оракулом і не можуть неявно замінити двійкове джерело.

Contract 12.0 вивів SID8/Sens8/Function8 з активного виконання. Старий код є міграційним боргом, а не сумісним семантичним шляхом. Ратифікація контракту сама по собі не доводить завершення нативної міграції.

## Поточні фізичні докази на `main`

Ця карта описує обмежені механізми, а не прогрес, виведений лише з назв файлів чи зеленого build. Стан звірено на `main@59da64e7b275a5a64c8a1e7fdf8b669b8119480f` (28.10.2026); перед використанням як поточного стану перевіряй пізніші злиття та їхній CI. Кожне «є» нижче має зазначене фізичне джерело перевірки.

| Вертикаль | Реалізовано й перевіряється | Чого це ще не доводить |
|---|---|---|
| Фізичний reader | Потоковий bounded T5M admission; codec; D2 AST; точні позиції слова, байта і трита; CLI перегляду/пакування та D2-перевірки. Тести: `scripts/test-t5madmission.sh`, `scripts/test-t5m.pas`, `scripts/test-d2source.sh`, `scripts/test-physloc.sh`, `scripts/test-t5m-cli.sh`. | Загальне виконання `.sens`, довільний source round-trip або семантичну правильність усіх форм. |
| Доменне зіставлення | Український source reader, індекси таблиць, AST census, фізичний T5M→D2 binder та оглядач із точними фізичними інтервалами (`wsm.source`, `wsm.bind*`, `wsm.binarybind`, `wsm.binarylocbind`, `sensbinary`). Перевірки включено у FPC та окремий CLI workflow. | Саме зіставлення координат не доводить допустимість виклику чи закон для непідтриманих доменів. |
| D3 evaluator | `wsm.nativeeval` виконує вузький набір D3-форм; `wsm.binaryexec` передає підтримані фізичні `.sens` T5M/D2-форми через exact-domain координати до цього evaluator. Докази: `scripts/test-nativeeval.pas`, `scripts/test-binaryexec.sh`, `evidence/nativeeval-g3-2`. | Повний runtime, загальну quote/string/number семантику, довільну програму, замикання/apply або Core4 execution. |
| Середовище й сесія | Reference-counted фрейми, source session API, D3 executor для багатоформових запитів, багаторядковий ввід і приватний host packet framing з обмеженою чергою у `wsm.envframe`, `wsm.session`, `wsm.sessiond3`, `wsm.lineinput`, `wsm.sessionwire`. | Повний інтерактивний REPL із bindings користувача, closures і всіма SENS формами; transport не є мовною семантикою. |
| Core4 | Pinned source admission, суворий український AST parse, приватний структурний SIR1 та утиліта `senscore4`; постійний FPC workflow `core4-source-admission`. | Виконання бібліотечних визначень Core4. Pascal не повинен копіювати ці визначення. |
| IR і компіляція | `sensc` формує/перевіряє/оглядає приватний структурний SIR1; окремий `wsm.exactir` будує ExactIR із точних domain-qualified координат для майбутнього lowering. Тести: `scripts/test-compiler.sh`, `scripts/test-exactir.sh`. | Семантична викличність для всіх вузлів, виконуване IR, lowering, executable output або native backend. |
| Пам'ять, діагностика, образи | Native mark/sweep механізм, roots/handles, physical debug/fault snapshots та їхня українська проєкція (`wsm.uktrace`), обмежений lexical-frame snapshot і окремий bounded GC stress profile. | Інтеграцію evaluator з GC, повний debugger protocol, образ виконуваної системи чи benchmark SENS execution. |

`scripts/test.sh`, `.github/workflows/fpc-headless.yml` і окремий `core4-source-admission` workflow збирають/перевіряють свої явно перелічені механізми. FPC PASS доводить саме ці кроки на перевіреному SHA; він не є автоматичним семантичним паритетом із SENS.

## Наступні інтеграційні кроки

1. Завершити узгодження Contract 12 із pin records та прибрати активні legacy-маршрути лише на основі точних негативних доказів.
2. Розширювати двійкове виконання від наявного вузького T5M/D2→D3 містка тільки через окремі точні domain/law докази; невідомі форми й далі відхиляти.
3. Розвивати exact-domain admission і викличність тільки за законами SENS, із відмовами для невідомих/непідтриманих координат.
4. Довершити окремі CLI/REPL поверхні, зберігши явну різницю між українською проєкцією та фізичним `.sens` input.
5. Лише після виконання реальних визначень із pinned Core4 можна заявляти підтримку Core4; лише після persistent read–eval–print з реальним evaluator можна заявляти повний REPL.
6. Перетворити ExactIR на семантично допущене виконуване подання; lowering/native codegen, інтеграція GC та системні образи потребують окремих перевірюваних вертикальних задач.

Відкриті основні задачі: [#41 epic](https://github.com/juv4uk/wsm-lazarus/issues/41), [#42 reader](https://github.com/juv4uk/wsm-lazarus/issues/42), [#43 binder](https://github.com/juv4uk/wsm-lazarus/issues/43), [#44 runtime](https://github.com/juv4uk/wsm-lazarus/issues/44), [#45 Core4](https://github.com/juv4uk/wsm-lazarus/issues/45), [#46 REPL/session](https://github.com/juv4uk/wsm-lazarus/issues/46), [#47 compiler/backend](https://github.com/juv4uk/wsm-lazarus/issues/47). [#48 пам'ять/debugger/image](https://github.com/juv4uk/wsm-lazarus/issues/48) закрита після кількох обмежених substrate-зрізів; це не означає, що повну підсистему завершено. Вузький місток фізичного двійкового виконання реалізований у [#76](https://github.com/juv4uk/wsm-lazarus/issues/76); його межі не означають загального виконання SENS.

## Правила розвитку

- Не виводити сенс зі spelling, ширини, десяткового числа, позиції в таблиці або backend opcode.
- Не повертати SID8, не створювати власний реєстр законів і не перетворювати Core4 на Pascal-визначення.
- Зберігати негативні тести, exact-width координати, походження та позиційну діагностику.
- Кожне нове твердження про виконання має посилатися на артефакт, який реально виконав форму; структурний парсер чи transport не є runtime.
- Не створювати release/tag без окремої вказівки власника.
