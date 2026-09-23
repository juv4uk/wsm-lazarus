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

| surface | upstream identity source | upstream meaning/law source | failing witness | classification |
|---|---|---|---|---|
| `quote` | `semantic-registry.lisp` `00000001` | `lib/core1.lisp` `C1-QUOTE-NAMEP`/`C1-EVAL` | `scripts/test-eval.pas` test (1) | substrate-required (special form) |
| `lambda` | `semantic-registry.lisp` `00001000` | `lib/core1.lisp` `C1-LAMBDA-NAMEP`/`C1-EVAL` | test (7) | substrate-required (special form) |
| `cond` | `semantic-registry.lisp` `00000111` | `lib/core1.lisp` `C1-COND-NAMEP`/`C1-EVCON` | test (4), (5) | substrate-required (special form, fail-closed on exhaustion) |
| `cons` | `semantic-registry.lisp` `00000100` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`CONS`) | test (2) | substrate-required (primitive) |
| `car` | `semantic-registry.lisp` `00000101` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`CAR`) | test (2) | substrate-required (primitive) |
| `cdr` | `semantic-registry.lisp` `00000110` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`CDR`) | test (2), (8) | substrate-required (primitive) |
| `atom` | `semantic-registry.lisp` `00000010` | `lib/core1.lisp` `C1-APPLY-PRIMITIVE` (`ATOM`) | test (3), (8) | substrate-required (primitive) |

Разом: **7 admitted IDs**, точно ті, що `EvalContextInit` резолвить
(`quote`, `cons`, `car`, `cdr`, `cond`, `lambda`, `atom`) — не менше, не
більше.

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
