# Революція логіки в my-lisp: піраміда () → бінарна → арифметична → множинна
# The Logic Revolution in my-lisp: the pyramid () → binary → arithmetic → multiplicity

**Дата / Date:** 2026-09-18
**Автор / Author:** agent (big-pickle) — переказ розуміння власника, звірений із комітами `my-lisp` за 2026-09-14…18
**Статус / Status:** осмислення (understanding note), не authority; authority живе в `my-lisp` (ADR-004, ADR-007, контракти в `contracts/`) та в піні fa9bd875
**Споживається / Consumed by:** `wsm-lazarus` (5-й субстрат, FPC) та `wsm-graalvm` (4-й субстрат, GraalVM)

---

## 1. Суть / The point

`my-lisp` здійснює революцію не «в механіці мови», а **в тому, звідки мова бере свою логіку**. Історична Lisp-спадщина будувала істину на сполученій парі «`t` / `()`»: реалізація мала власний булевий тип (`Value::Bool`), «істина» була власністю рантайму, а `()` примушувалося грати роль FALSE. Революція полягає в тому, що логіка більше **не належить субстрату** — вона виводиться із самого первинного значення і стає Lisp-owned фактом (сховище, witness, контракти).

The historical Lisp heritage built truth on the married pair `t` / `()`: the implementation owned a boolean type (`Value::Bool`), "truth" was the runtime's property, and `()` was forced into the role of FALSE. The revolution moves logic out of the substrate: logic is derived from the primary value itself and becomes Lisp-owned fact (registry, witness, contracts).

---

## 2. Піраміда / The pyramid

```text
             ()
   первинне значення; неможливо описати;
   пронизує всі шари (Surfacing Law — обчислюється в себе)
             │
   ┌─────────┴─────────┐
   бінарна логіка       (частково) арифметична
   └─────────┬─────────┘
             ▼
   арифметична логіка    exact rationals; 0/1 = НЕ, 1/1 = ТАК
             │
   ┌─────────┴─────────┐
   множинна логіка      class-membership: (class-membership symbol member)
```

### 2.1 Канон 0: `()` як первинне значення / Canon 0: `()` as the primary value

Authority: `docs/adr/ADR-004-CLOSED-MCCARTHY7-CORE.md` (§4.0, §4.1), прийнято 2026-09-05.

- `()` — **первинний канонічний ґрунт** (canonical ground): до того, як будь-яка операція може сполучити, розібрати чи обчислити, існує `()`.
- `eval(())` → `()` (**Self-Evaluating Law**) — обчислюється саме в себе, без лапок. Первинний літерал форми.
- У `my-lisp` `nil` **не є** канонічною тотожністю, не є truth-value, не є автономним примітивом. Історичне написання `nil` — щонайбільше foreign compatibility alias.
- `()` неможливо описати «через щось зовнішнє» — воно визначає себе через структурні закони (`(атом? ()) → #t`, `(pair? ()) → #f`, `(proper-list? ()) → #t`).

- `()` is the **canonical ground**: before any operation can construct, deconstruct, or evaluate, there is `()`.
- `eval(())` → `()` (**Self-Evaluating Law**) — it evaluates to itself, without quoting.
- `nil` is **not** a canonical identity in `my-lisp`, not a truth-value, not an autonomous primitive; historical `nil` is at most a foreign compatibility alias.
- `()` cannot be described "through something external" — it defines itself through structural laws.

### 2.2 Бінарна логіка / Binary logic

- Замкнене ядро McCarthy-7 (ADR-004 §2): рівно сім семантичних тотожностей `{ PRIM_QUOTE, PRIM_ATOM, PRIM_EQ, PRIM_CAR, PRIM_CDR, PRIM_CONS, PRIM_COND }`. Восьмий примітив додати заборонено.
- Бінарне розрізнення (чи значення є членом класу / чи здатне до операції) — це **спостереження**, а не судження реалізації.

- Closed McCarthy-7 core (ADR-004 §2): exactly seven semantic identities `{ PRIM_QUOTE, PRIM_ATOM, PRIM_EQ, PRIM_CAR, PRIM_CDR, PRIM_CONS, PRIM_COND }`. No eighth primitive may be admitted.

### 2.3 Арифметична логіка / Arithmetic logic

Authority: `contracts/exact-q-binary-contract.lisp`, `contracts/mathematical-result-taxonomy.lisp`; коміт `509a236a` (#216), 2026-09-18.

- Математичний результат — **exact rational**: `0/1` = НЕ (NO), `1/1` = ТАК (YES). Число не є упакованим булевим значенням.
- Математичний об'єкт ≠ його апроксимація (#225). `pi` та `314159/100000` — різні математичні об'єкти, навіть коли друге виконує роль апроксимації першого.
- Друк `1/1` → `"1"` і `0/1` → `"0"` — це canonical spelling, а не зміна семантичного значення.
- Числа в M0 (tier-1) вміщуються в `int64`-раціонали; overflow-літерали (`conformance.lisp` рядки 36–38, 226) — tier-2 → BigInt переноситься в M1-BIGINT.

- Mathematical result is an **exact rational**: `0/1` = NO, `1/1` = YES. A number is not a wrapped boolean.
- A mathematical object ≠ its approximation (#225).
- Printing `1/1` as `"1"` is canonical spelling, not a semantic change.
- Tier-1 numbers fit `int64` rationals; overflow literals are tier-2 → BigInt lives in M1-BIGINT.

### 2.4 Множинна (класова) логіка / Set-theoretic (class) logic

Authority: `contracts/structural-observation-contract.lisp`; коміти `d4cdda1a` (#369) та merge `f04a592a` (#352), 2026-09-17…18.

- `symbol?` повертає явний результат **`(class-membership symbol member)` / `(class-membership symbol nonmember)`**, а не загальну істинність.
- String-предикати та їхні споживачі мігровані на той самий explicit class-membership (#352): результат є даними з алгебри членства, а не bool-перетворенням.
- `generic-truth-coercion` заборонено; `control-dispatch` вимагає explicit-result-equality.

- `symbol?` returns the explicit result **`(class-membership symbol member)` / `nonmember`** instead of generic truthiness.
- String predicates and consumers migrated to the same explicit class-membership (#352).
- `generic-truth-coercion` forbidden; `control-dispatch` requires explicit-result-equality.

---

## 3. Демонтаж t/()-моделі / Dismantling the t/() model (#216/#220)

Коміти за 2026-09-14…18 систематично виносять «істину» з рантайму в Lisp-owned факти:

| # | Коміт / commit | Що зроблено / What changed |
|---|---|---|
| 1 | `b16c545b` (#632) | P0: суперсид historical 1016 `T`-фікстури через Lisp witness |
| 2 | `509a236a` (#216) | witness canonical 0/1 і 1/1 source spellings |
| 3 | `bf00324c` (#253) | Canon-закони виконавні, layered, без generic truthiness, тричастинний cond |
| 4 | `d4cdda1a` (#369) | ratify symbol class-membership |
| 5 | `f04a592a` (merge, #352) | міграція string-predicate споживачів на class-membership |
| 6 | `5a8fa679` (#647), `740cfa07` | retire stale scientific Rust truth sentinels |
| 7 | `24ce8e1f` (#305) | retire stale result-status semantic oracles |
| 8 | `f78e337e` (#626) | make native-first pair-head classification total |
| 9 | `f724bfa5` (#505) | native-first classifier з evaluator fallback |

Спільний вектор: **value = об'єкт спостереження, а не носій істини**. Істина — це результат стосунку (member/nonmember, 0/1, 1/1), який мова може спостерігати рівними (? `тотожне?`) і записувати як Lisp-дані.

Common vector: **a value is an object of observation, not a carrier of truth**. Truth is a relation-result (member/nonmember, 0/1, 1/1) that the language observes by equality (`тотожне?`) and records as Lisp data.

---

## 4. Поверхні як проєкції, не переклади / Surfaces as projections, not translations (ADR-007)

Authority: `docs/adr/ADR-007-MEANING-FIRST-SURFACES.md`; коміти 1050/1051/1052 direct-peer (`b18a4e62`, `e2062943`, `3b71afc7`), 2026-09-18.

- Семантична тотожність первинна; людські написання — поверхневі назви тієї самої identity.
- `1052` `string->symbol` / `текст-у-символ` стає **registry-driven direct peer**: банкрут bridge-визначення `(define текст-у-символ string->symbol)` — тепер тотожність фіксує реєстр (`lib/surface/semantic-registry.lisp`), а не англійське ядро.
- Піраміда поверхонь: `car` / `перше` / `ādi` — три незалежні людські проєкції **однієї** semantic identity, жодна не є джерелом іншої.

- Semantic identity is primary; human spellings are surface names of that identity.
- 1052 `string->symbol` / `текст-у-символ` becomes a **registry-driven direct peer**: the bridge `(define текст-у-символ string->symbol)` is retired; identity lives in the registry, not in an English core.
- `car` / `перше` / `ādi` are three independent surface projections of one semantic identity.

---

## 5. Наслідки для FPC-свідка (wsm-lazarus) / Consequences for the FPC witness

1. **`kVNil` ≠ `kUnbound`.** Вже закладено в `src/wsm.values.pas`: `()` (kVNil) і `#<unbound>` (kUnbound) — різні kind-и. Прямо охороняє межу революції: `()` не є «false» і не є «missing».
2. **Числа = exact rationals.** M0-EVAL повертає qnum/qden з gcd-нормалізацією; значення `0/1` і `1/1` — уже канонічні ТАК/НЕ для tier-1 предикатів клас-членство; споживаються як дані, не як bool.
3. **ID-first dispatch.** Як registry-driven peers у my-lisp, так і свідок: диспетчеризація за числовими semantic IDs з реєстру, жодних hardcoded spellings `car`/`cdr`/`equal?` у коді.
4. **ErrorKind-паритет.** `(+ 2 3)` має спостерігатися однаково з Graal-свідком (error-kind Type, канонічний ID), бо т/() і генерик-truth зникли з обох.
5. **Pin fa9bd875.** Поточний authority-пін (= commit `fa9bd875…`, canonical COND #633) — до суперсиду 1016 та class-membership merge-міграцій; наступний pin-bump наздожене ці контракти (для M0 достатньо: свідок споживає `()`/unbound/pair/символ/число — foundation не змінюється між пінами).
6. **Без generic truthiness у свідку.** Жоден bridge-шар FPC не має права вводити t/()-модель як звичний bool; будь-який предикат віддає клас-членство або exact-Q.

1. **`kVNil` ≠ `kUnbound`.** Already in `src/wsm.values.pas`: `()` and `#<unbound>` are distinct kinds, guarding the revolution's boundary.
2. **Numbers are exact rationals.** M0-EVAL returns gcd-normalized qnum/qden; `0/1` and `1/1` are already canonical NO/YES for tier-1 class-membership predicates, consumed as data.
3. **ID-first dispatch.** Like registry-driven peers, the witness dispatches on numeric semantic IDs; no hardcoded `car`/`cdr`/`equal?` spellings.
4. **ErrorKind parity.** `(+ 2 3)` must observe identically in Graal and FPC witnesses (error-kind Type, canonical ID).
5. **Pin fa9bd875.** The current authority pin predates 1016 supersession and class-membership merges; the next pin-bump will absorb them (M0 foundation is unchanged between pins).
6. **No generic truthiness in the witness.** FPC bridge layers must not reintroduce the t/() model as a familiar bool.

---

## 6. Відкриті питання для власника / Open questions for the owner

1. Чи правильно вловлено, що «бінарна → арифметична → множинна» — це **порядок виведення** (спочатку ключове відношення 0/1–1/1, потім числа як exact-Q, потім класи), а не три незалежні логіки?
2. Чи міграцію string-predicates до class-membership (merge `f04a592a`) тягнути у свідок як контракт-вимогу вже зараз, чи достатньо pins `fa9bd875` (де цього ще нема)?

---

## 7. Джерела / Sources

- `my-lisp`: `docs/adr/ADR-004-CLOSED-MCCARTHY7-CORE.md`, `docs/adr/ADR-007-MEANING-FIRST-SURFACES.md`
- `my-lisp`: `contracts/exact-q-binary-contract.lisp`, `contracts/mathematical-result-taxonomy.lisp`, `contracts/structural-observation-contract.lisp`
- `my-lisp`: `docs/TRUTH-SENTINEL-INVENTORY-2026-09-17.md`
- `my-lisp`: `lib/surface/semantic-registry.lisp` (IDs 0104, 1016, 1023, 1050–1052 тощо)
- Коміти my-lisp за 2026-09-14…18 (SHA: `509a236a`, `bf00324c`, `d4cdda1a`, `b16c545b`, `f04a592a`, `5a8fa679`, `24ce8e1f`, `f78e337e`, `f724bfa5`, `b18a4e62`, `e2062943`, `3b71afc7`)
- Пін authority субстратів: `fa9bd875` («M1: migrate clear-domain core consumers to canonical COND (#633)»)