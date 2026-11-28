# Нативні пакети Free Pascal

Це FPMake-пакети **поверх наявних units**, а не копії вихідного коду та не
Lazarus `.lpk`. Один FPMake-manifest описує:

| Пакет | Unit | Залежності |
|---|---|---|
| `wsm-source` | `wsm.source` | FPC RTL |
| `wsm-domain` | `wsm.domain` | `wsm-source`, FPC RTL |

Джерела залишаються авторитетно в `../src/`; package manifest збирає їх
без переміщення. Залежність між пакетами задана двома способами: package
dependency для FPMake та unit dependency/unit search path для компілятора.
Обидва пакети є headless і не потребують Lazarus/LCL.

## Збірка та перевірка

Потрібен Free Pascal з установленим `fpmkunit` (у стандартному Debian/
Ubuntu пакеті це надає `fp-units-base`). З кореня репозиторію:

```sh
bash scripts/test-fpc-packages.sh
```

Сценарій збирає локальний FPMake driver, виконує справжній
`fpmake compile`, а потім компілює окрему consumer-програму, використовуючи
лише каталоги units двох пакетів. Артефакти потрапляють у `build/fpc-packages/`,
не в Git-гілку. CI використовує FPC 3.2.2 як контрольну версію.

## Контракти API та володіння пам'яттю

- `wsm.source.ReadUkrainianSource` приймає `RawByteString` з UTF-8 байтами
  й повертає `TSourceDocument`. Документ належить викликачу і має бути
  звільнений через `Free`; AST володіє своїми дочірніми вузлами.
  `ESourceError` повідомляє байтову позицію та рядок.
- `wsm.domain.ExactKey` перетворює точний двійковий запис у record
  `(Width, Bits)`, не втрачаючи провідних нулів. `LoadDomainTable`
  повертає цілісну таблицю або помилку; часткова таблиця не публікується.
- `wsm-domain` не може збиратися без `wsm-source`: це перевіряється
  package dependency та прямою залежністю unit.

Ці пакети не реалізують SENS evaluator, семантичний dispatch, декодер
фізичного `.sens`, Core4 runtime чи повний компілятор. Вони лише
пакують перевірювані host-механізми, що вже є в репозиторії.

## Питання для перевірки розуміння

1. Чому `TDomainKey.Width` є частиною ідентичності, а не просто підказкою?
2. Хто звільняє `TSourceDocument` і хто володіє його дочірніми вузлами?
3. Чому `wsm-domain` має залежати від `wsm-source`, а не копіювати reader?
4. Що саме доводить зелений пакетний CI — і чого він не доводить?
