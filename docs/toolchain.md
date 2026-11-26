# FPC toolchain boundary

## Supported baseline

M0.2 is developed against **Free Pascal 3.2.2** on Linux x86-64.

### Стан релізів FPC на 26.11.2026 — що саме випущено

- **FPC 3.2.4 має фінальний upstream source-tag**: `release_3_2_4`, commit `66940ee65006538dba16b4c584d3cfb1cc08985e`, автор Michael Van Canneyt. У commit змінено package/compiler version із `3.2.4-rc2` на `3.2.4`; GitLab pipeline #3041687631 пройшов стадії `compilercycle` та `buildandtest`.
- **Дистрибуція готових пакетів ще не синхронізована з source-tag.** SourceForge `Source/3.2.4` містить `src324.zip` (44.1 MB) та README із заголовком Version 3.2.4 і переліком платформ. Водночас офіційна сторінка Download досі називає 3.2.2 останнім готовим release package і перелічує лише його бінарні пакети. Тож 3.2.4 уже не можна називати «лише RC2», але також не можна припускати, що готовий інсталятор для кожної потрібної платформи вже опублікований.
- **3.2.2 залишається базою наявних вимірів**, а не найновішим source release. Енергетичні серії, ELF evidence та Core1 AOT уже pin-ені до 3.2.2; їх не переписуємо заднім числом. Додаймо 3.2.4 як окрему candidate baseline: зібрати з pinned source tag, зафіксувати compiler/RTL/toolchain і повторити ті самі докази перед будь-яким перемиканням бази.
- **3.3.1 x86_64-embedded — окремий development snapshot**, не змішувати з release_3_2_4. Він потрібен для P0 UEFI/embedded probe, а не для загального benchmark порівняння.
- **3.4.0 не є близьким.** У наявних матеріалах команди Lazarus 2025/2026 немає підтвердженої дати цього релізу; не будувати план на припущенні про близький випуск.
- **CI pin лишається окремою проблемою:** `apt-get install fp-compiler` без версії може тихо змінити compiler на runner-і. Поки CI не перевіряє точний `fpc -iV`, evidence не є повністю відтворюваним. Це спільний workflow hook; зміну треба робити окремою задачею й перевіряти на всіх власниках цього hook.

Джерела: [upstream GitLab release tag](https://gitlab.com/freepascal.org/fpc/source/-/tags/release_3_2_4), [tag commit and passed compiler/build pipelines](https://gitlab.com/freepascal.org/fpc/source/-/commit/66940ee65006538dba16b4c584d3cfb1cc08985e), [SourceForge source package 3.2.4](https://sourceforge.net/projects/freepascal/files/Source/3.2.4/), [official download page](https://www.freepascal.org/download.html), [official development snapshots](https://www.freepascal.org/develop.html).

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
