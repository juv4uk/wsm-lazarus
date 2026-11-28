# Нативні пакети Free Pascal

Це FPMake-пакети **поверх наявних units**, а не копії вихідного коду та не
Lazarus `.lpk`. Один FPMake-manifest описує:

| Пакет | Unit | Залежності |
|---|---|---|
| `wsm-source` | `wsm.source` | FPC RTL (частина компілятора) |
| `wsm-domain` | `wsm.domain` | `wsm-source`; FPC RTL (частина компілятора) |

Джерела залишаються авторитетно в `../src/`; package manifest збирає їх
без переміщення. Залежність між пакетами задана через `P.Dependencies`,
а `UnitPath` забезпечує пошук залежного unit. Для кожного пакета
`UnitDir` визначає окремий каталог компіляторських артефактів.
Базовий RTL не оголошується окремою fppkg-залежністю: він постачається
самим FPC toolchain. Обидва пакети є headless і не потребують Lazarus/LCL.

## Збірка, встановлення та перевірка

Потрібен Free Pascal з `fpmkunit` та його FCL-залежностями. У Debian/
Ubuntu для цього контрольного середовища встановлюються `fp-compiler`,
`fp-units-base` і `fp-units-fcl` (останній надає, зокрема, unit
`process`, потрібний FPMake).

З кореня репозиторію:

```sh
bash scripts/test-fpc-packages.sh
```

Сценарій збирає FPMake driver і запускає справжній `fpmake buildinstall`
з ізольованими `--prefix` та `--unitinstalldir` у
`build/fpc-packages/stage/`. Після встановлення незалежна consumer-програма
компілюється **лише** з цього каталогу installed units, без доступу до
`src/` або package-local build outputs. Артефакти тесту не пишуться у Git;
`build/` і package-local `units/` є локальними build outputs.

GitHub Actions workflow **FPC packages** запускається через
`workflow_dispatch`: перевірник FPC-workflow у репозиторії має бюджет
`pull_request`, тому новий workflow не додає ще один автоматичний PR-run.
Для ручної перевірки вибрати гілку з package changes у запуску workflow.

## Контракти API та володіння пам'яттю

- `wsm.source.ReadUkrainianSource` приймає `RawByteString` з UTF-8 байтами
  й повертає `TSourceDocument`. Документ належить викликувачу і має бути
  звільнений через `Free`; AST володіє своїми дочірніми вузлами.
  `ESourceError` повідомляє байтову позицію та рядок.
- `wsm.domain.ExactKey` перетворює точний двійковий запис у record
  `(Width, Bits)`, не втрачаючи провідних нулів. `LoadDomainTable`
  повертає цілісну таблицю або помилку; часткова таблиця не публікується.
- `wsm-domain` залежить від `wsm-source`; перевірка доводить, що обидва
  units встановлюються та можуть бути використані окремою програмою.

Ці пакети не реалізують SENS evaluator, семантичний dispatch, декодер
фізичного `.sens`, Core4 runtime чи повний компілятор. Вони лише
пакують перевірювані host-механізми, що вже є в репозиторії.

## Питання для перевірки розуміння

1. Чому `TDomainKey.Width` є частиною ідентичності, а не просто підказкою?
2. Хто звільняє `TSourceDocument` і хто володіє його дочірніми вузлами?
3. Чому `wsm-domain` має залежати від `wsm-source`, а не копіювати reader?
4. Що саме доводить зелений пакетний CI — і чого він не доводить?
