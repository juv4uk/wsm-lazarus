# G3.2: фізичні exact-domain свідки

Джерело законів: pinned SENS `1f1bf676eeac605e065035d9dd2adaae807f1788`, Contract 12.0. Це не SID8/text oracle. `witness.json` зберігає 19 позитивних і 5 негативних порівнянь фізичного `.sens` запуску з обмеженим FPC evaluator. Український source є проєкцією, а `.sens` — carrier від pinned Zig/T5M. Далі виконується саме physical файл у чистому SENS session.

`lazarus_base_sha` — база checkout до коміту; `native_source_sha256` фіксує змінений Pascal unit. Окремо зафіксовано хеші обох фактичних бінарників. `fpc-gate.log` — локальний повний headless gate на FPC 3.2.2, range/overflow/I/O checks і heaptrc для нового unit: 61 перевірка, 0 невивільнених блоків.

Перевірка носіїв і журналів із цього каталогу: `sha256sum -c SHA256SUMS`. Навігаційний README створений після маніфесту; сам він не є сирим доказом.

[Методика й межі](../../docs/native-eval-g3-2.uk.md). Тут немає доказу всього G3, канонічного reader Pascal, виконання Core4 або готового REPL. Назви помилок/exit обох механізмів можуть відрізнятися: негативний свідок підтверджує лише відмову, не повну error parity.

Після code review gate посилено: негатив потребує саме exit 1, очікуваного семантичного фрагмента й позиції фізичної форми; signal/loader failure відхиляються. `native-build.log` підтверджує свіжу FPC-збірку всередині gate. Хеш SENS binary — ідентифікація, не автоматичний доказ побудови з source; provenance збірки надається оператором окремо. Сім regression-тестів proof gate пройдені локально.
