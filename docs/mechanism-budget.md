# Mechanism budget — wsm-lazarus (issue #9)

Кожен semantic ID, який `src/wsm.eval.pas` реально admits (`ResolveAdmittedId`
у `EvalContextInit`), мусить мати рядок тут. `scripts/check-mechanism-budget.sh`
механічно звіряє цей файл проти реального коду — жоден ID не може існувати
в одному без відповідника в іншому.

Правило допуску (issue #9): кожен новий ID — окремо, лише якщо є upstream
identity source, upstream meaning/law source, конкретний failing witness,
і classification. Без цього — не додавати "про запас".

## Reserved-nil row

`00000000` — зарезервований, порожній рядок у самому
`semantic-registry.lisp` (`(en ()) (ук ()) ...`). Не admitted тут: не
відповідає жодній функції, яку цей evaluator реалізує.

## Admitted IDs

Це перехідний реєстр поверхневих назв восьмибітної спадкової таблиці,
а не дозвіл ототожнювати ці коди з точними доменами D1–D10.
Семантичну владу та бітову ширину визначає SENS, не цей Pascal-адаптер.

| surface | upstream identity source | upstream meaning/law source | failing witness | classification |
|---|---|---|---|---|
| `quote` | `semantic-registry.lisp` `00000001` | `lib/core1.lisp` `C1-QUOTE-NAMEP`/`C1-EVAL` | `scripts/test-eval.pas` test (1) | substrate-required (special form) |
| `lambda` | `semantic-registry.lisp` `00001000` | `lib/core1.lisp` `C1-LAMBDA-NAMEP`/`C1-EVAL` | test (7) | substrate-required (special form) |
| `cond` | `semantic-registry.lisp` `00000111` | `lib/core1.lisp` `C1-COND-NAMEP`/`C1-EVCON` | test (4), (5) | substrate-required (special form, fail-closed on exhaustion) |
| `cons` | `semantic-registry.lisp` `00000100` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`CONS`) | test (2) | substrate-required (primitive) |
| `car` | `semantic-registry.lisp` `00000101` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`CAR`) | test (2) | substrate-required (primitive) |
| `cdr` | `semantic-registry.lisp` `00000110` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`CDR`) | test (2), (8) | substrate-required (primitive) |
| `atom?` | `semantic-registry.lisp` `00000010` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`ATOM`) | test (3), (8) | substrate-required (primitive) |
| `eq?` | `semantic-registry.lisp` `00000011` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`EQ`), used directly by `C1-ERRORP` | test (9) | substrate-required (primitive) |
| `define` | `semantic-registry.lisp` `00001001` | `lib/core1.lisp` `C1-DEFINE-NAMEP`/every top-level `(DEFINE name ...)` | `scripts/test-eval.pas` def tests | substrate-required (special form: top-level binding) |
| `def` | `semantic-registry.lisp` `00001011` | `lib/canon.lisp`'s `(def name (lambda ...))` convention; compatibility alias SID for `define` | `scripts/test-eval.pas` def tests | substrate-required (special form: top-level binding) |
| `label` | pinned `semantic-registry.lisp` `10101010` | pinned `lib/core1.lisp` binary LABEL heads | `scripts/test-eval.pas` actual Core1 reader | transitional (legacy 8-bit profile; not ratified modern D8) |

Разом: **11 admitted IDs**, точно ті, що `EvalContextInit` резолвить
(`quote`, `cons`, `car`, `cdr`, `cond`, `lambda`, `atom?`, `eq?`, `define`,
`def`, `label`) — не менше, не більше.

## Аудит-запис: історичний Core1 8-bit зріз

У пінованому корпусі Core1 голови операторів — точні восьмибітні
`kSid`, які лише зіставляються за ідентичністю в Pascal. Їх не можна
автоматично вважати новими ратифікованими кодами D1/D3/D4/D8.
Семантичний оракул сучасних доменів належить нативному SENS.

## Аудит-запис: `define`/`def` (issue #30, 2026-09-23)

Admitted для failing witness `lib/canon.lisp` (кожен `canon-law-*` —
named top-level визначення) і, ще ближче, Core1's own `C1-EVAL` family
(#27): `C1-EVAL` викликає `C1-EVLIS`/`C1-EVCON`/`C1-APPLY`/`C1-LOOKUP`,
визначені ОКРЕМИМИ top-level `DEFINE`, а ті викликають `C1-EVAL` назад
-- genuinely mutual recursion across separate definitions, що
неможливо виразити self-application-трюком (той, що вже працює для
#26's трьох незалежних helper-функцій). `define`/`def` -- ДВІ окремі
SID (`00001001`/`00001011`), обидві вже в реєстрі, диспетчеризуються
однаково (top-level binding в persistent `TGlobalEnv`, окремій від
лексичного `env`).

## Аудит-запис: `eq?` (issue #26, 2026-09-23)

Admitted при спробі виконати РЕАЛЬНІ форми з пінованого `core1.lisp`
(#26's "не синтетичні фіксчури"): `C1-ERRORP` буквально викликає
`(EQ (CAR VALUE) (QUOTE C1-ERROR))`. `eq?` вже був у реєстрі (SID
`00000011`), просто не мав диспетчеризації в `wsm.eval.pas` до цього
коміту — конкретний, а не "про запас" випадок.

## Аудит-запис: чому `-`/`=` були прибрані (2026-09-23)

Попередня версія `wsm.eval.pas` (M0.6, до цього аудиту) admits також
`-` (MINUS, `00001101`) і `=` (NUMEQ, `00011100`). Аудит issue #9
показав: жоден з них не має upstream-owned failing witness —
`lib/core1.lisp`'s `C1-APPLY-PRIMITIVE` admits лише `LIST`/`NOT`/
`ATOM`/`EQ`/`CONS`/`CAR`/`CDR`, арифметики там немає взагалі. Обидва
були додані виключно заради власного deep-recursion тесту цього
модуля (лічити вниз через `-`, перевіряти `= n 0`) — саме "про запас"
допущення, яке issue #9 прямо забороняє. Прибрано; той самий тест
переписано так, щоб обходити pre-built список через `cdr`/`atom`,
без жодної арифметики.

## `max-lisp-defined-host-debt`

Жоден з 7 admitted IDs не є "Lisp-defined behavior, перенесеним у
Pascal" — усі сім або спеціальні форми (`quote`/`lambda`/`cond`), або
прямі примітиви з `C1-APPLY-PRIMITIVE`. Інваріант тримається: **0**.
