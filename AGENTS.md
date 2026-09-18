# AGENTS.md — wsm-lazarus (FPC/Lazarus substrate witness)

## Статус репозиторію

П'ятий субстратний свідок семантичної влади `my-lisp`: **Free Pascal / Lazarus (FPC/LCL)**.
Лінія субстратів цього проєкту: Rust → Graal (Java) → WASM/C → FPGA → **FPC**.

Влада НЕ тут. Повноважні файли належать pinned `external/my-lisp`
(однаковий gitlink pin для всіх субстратів). Цей репозиторій лише свідчить:
`(canon-conforms?)` оцінюється на власному reader-у/eval-у і дає `t`.

## Мовна політика (owner directive, див. ecosystem AGENTS.md)

Людська документація — українською зі збереженням технічної англійської,
де це корисно. Machine identifiers, команди, цитати джерел, generated evidence
не переписуються; довкілля — пояснення українською.

## Дисципліна (глобальна, застосовна у кожному сесії)

- Agent Guard M0: перед write-heavy роботою читати
  `ecosystem/plans/AGENT-GUARD-M0.md`.
- Агенти НЕ читають цей репо як джерело authority — лише як свідок.
- Після кожного нетривіального фрагмента — питання на розуміння саме цього коду
  (тип → параметри → calling convention/memory layout → allocation → returned value).
- Ліцензія: ВОЛЬНІСТЬ для власних творів; текст LICENSE — дослівна канонічна копія,
  нічого не додавати/вилучати.

## Структура

```
wsm-lazarus/
├── external/my-lisp        ← gitlink submodule, pinned (той самий pin fa9bd875…)
├── refs/                   ← дзеркала wsm-graalvm/refs: registry-refs,
│                              mechanism budget, dependency manifest,
│                              tier1-baseline, sparse-authority-paths
├── src/                    ← wsm.*.pas: reader, values, eval, env, bigint
├── scripts/                ← ті самі гейти: test-tier1.sh, run-canon.sh,
│                              check-spelling-firewall.sh
├── docs/decisions/         ← ADR-и цього субстрата
└── gui/                    ← (M2, опційно) LCL-інспектор свідчень
```

## Семантичні рішення (на дату створення, деталі в ADR)

- _Канон-свідок ідентичний_: `(canon-conforms?)` → `t` з pinned `canon.lisp`.
  Не «паскаль-лісп працює», а «свідок згоден із контрактом».
- _Представлення значень_: A з плямою B — атоми tagged, пари/стрічки з арени.
- _TCO_: trampoline з самого початку як перманентне рішення субстрата.
- _BigInt_: чесна повнота exactness S1 — окрема вертикаль після tier-1;
  tier-1 фікстури не перевищують int64 (перевірено в conformance.lisp).