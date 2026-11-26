# FPC toolchain boundary

## Supported baseline

M0.2 is developed against **Free Pascal 3.2.2** on Linux x86-64.

### Стан релізів FPC на 26.11.2026 — і чому базою лишається 3.2.2

- **3.2.4 щойно позначений тегом** (`release_3_2_4`, «Set version to 3.2.4», приблизно середина листопада 2026) після довгого очікування: RC1 датований 2024 роком, RC2 — приблизно трьома місяцями раніше. Тобто це патч-реліз гілки 3.2, а не нова гілка.
- **3.4.0 не є близьким.** Команда Lazarus у листопаді 2025 прямо відповіла, що 3.4 не вийде того року; у квітні 2026 в `fpc-devel` тривало обговорення каденції релізів і відкритих merge request-ів, а не дати випуску.
- **Неофіційні збірки 3.3.1 існують** (щомісячні «community edition» зі trunk від стороннього мейнтейнера). Вони не є офіційним релізом FPC і не мають гарантій стабільності — тому в базову лінію вони не входять.

**Що з цього випливає для нас:** база лишається 3.2.2, бо саме на ній зібрані наявні виміри й докази (енергетичні серії, відтворюваність ELF, Core1 AOT). Перехід на 3.2.4 — окреме рішення, яке вимагає повторного прогону цих доказів, а не редагування числа в документі.

**Окрема відкрита межа:** CI-крок ставить компілятор командою `apt-get install fp-compiler` без фіксації версії й лише друкує `fpc -iV`. Поки версія не перевіряється, оновлення образу runner-а може тихо змінити компілятор під доказами про відтворюваність. Це зафіксовано як задачу, а не виправлено тут: файл workflow — спільний CI hook.

The headless witness must remain buildable without Lazarus/LCL. Lazarus is declared
for the later M2 inspector only and is not part of the M0.2 runtime dependency
closure.

## One-command path

After the pinned authority submodule has been synchronized:

```bash
./scripts/sync-authority.sh
./scripts/test.sh
```

`scripts/test.sh` checks the authority pin/sparse boundary, the no-LCL firewall,
builds `src/wsm.headless.lpr`, verifies deterministic CLI exit behavior, and
runs the reusable test skeleton.

## Scope

A GREEN M0.2 gate proves only that the FPC substrate/toolchain is ready. It does
**not** claim that the Lisp reader, evaluator, semantic registry bridge, Canon,
or conformance suite works. Those remain later roadmap gates.
