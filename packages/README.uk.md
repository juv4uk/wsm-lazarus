# Нативні пакети Free Pascal

Це FPMake-пакети **поверх наявних units**, а не копії вихідного коду та не
Lazarus `.lpk`. Один FPMake-manifest описує:

| Пакет | Unit | Залежності |
|---|---|---|
| `wsm-source` | `wsm.source` | FPC RTL |
| `wsm-domain` | `wsm.domain` | `wsm-source`, FPC RTL |

Джерела залишаються авторитетно в `../src/`; package manifest збирає їх
без переміщення. Залежність між пакетами задана двома способами: package
dependency визначає порядок FPMake-збірки, а `UnitPath` дає компілятору шлях
до зібраного `wsm.source`. Обидва пакети є headless і не потребують
Lazarus/LCL.

## Збірка та перевірка

Потрібен Free Pascal з `fpmkunit` та його FCL-залежностями. У Debian/
Ubuntu для цього контрольного середовища встановлюються `fp-compiler`,
`fp-units-base` і `fp-units-fcl` (останній надає, зокрема, unit
`process`, потрібний FPMake).

З кореня репозиторію:

```sh
bash scripts/test-fpc-packages.sh
```

Сценарій збирає локальний FPMake driver, виконує справжній
`fpmake compile`, а потім компілює окрему consumer-програму, використовуючи
лише каталоги units двох пакетів. Компіляторські артефакти створюються у
`packages/{wsm-source,wsm-domain}/units/` і виключені локальними
`.gitignore`; тимчасова програма FPMake та consumer — у
`build/fpc-packages/`. Жодні двійкові артефакти не призначені для Git.
CI використовує FPC 3.2.2 як контрольну версію.

## Контракти API та володіння пам'яттю

- `wsm.source.ReadUkrainianSource` приймає `RawByteString` з UTF-8 байтами
  й повертає `TSourceDocument`. Документ належить викликачу і має бути
  звільнений через `Free`; AST володіє своїми дочірніми вузлами.
  `ESourceError` повідомляє байтову позицію та рядок.
- `wsm.domain.ExactKey` перетворює точний двійковий запис у record
  `(Width, Bits)`, не втрачаючи провідних нулів. `LoadDomainTable`
  повертає цілісну таблицю або помилку; часткова таблиця не публікується.
- `wsm-domain` не може збиратися без `wsm-source`: це перевіряється
  package dependency та явним unit search path.

Ці пакети не реалізують SENS evaluator, семантичний dispatch, декодер
фізичного `.sens`, Core4 runtime чи повний компілятор. Вони лише
пакують перевірювані host-механізми, що вже є в репозиторії.

## Питання для перевірки розуміння

1. Чому `TDomainKey.Width` є частиною ідентичності, а не просто підказкою?
2. Хто звільняє `TSourceDocument` і хто володіє його дочірніми вузлами?
3. Чому `wsm-domain` має залежати від `wsm-source`, а не копіювати reader?
4. Що саме доводить зелений пакетний CI — і чого він не доводить?
