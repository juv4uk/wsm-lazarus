# Перевірені профілі: індекс

Згенеровано `scripts/gen-verified-index.sh` — не редагувати руками.
Кожен рядок — наявний модуль і його тест; відповідність перевіряє
`scripts/check-verified-modules.sh`.

| модуль | тест |
|---|---|
| `src/wsm.verifiedd6doubleadd.pas` | `scripts/test-verifiedd6doubleadd.sh` |
| `src/wsm.verifiedd6sub1.pas` | `scripts/test-verifiedd6sub1.sh` |
| `src/wsm.verifiedir.pas` | — (історична назва тесту) |
| `src/wsm.verifiedless.pas` | `scripts/test-verifiedless.sh` |
| `src/wsm.verifiedminmax.pas` | `scripts/test-verifiedminmax.sh` |
| `src/wsm.verifiedmul.pas` | `scripts/test-verifiedmul.sh` |
| `src/wsm.verifiedquot.pas` | `scripts/test-verifiedquot.sh` |
| `src/wsm.verifiedrest.pas` | `scripts/test-verifiedrest.sh` |
| `src/wsm.verifiedsub.pas` | `scripts/test-verifiedsub.sh` |
| `src/wsm.verifiedwidecontext.pas` | — (історична назва тесту) |

## Агрегатори

- `scripts/test-verified-all.sh` — усі `test-verified*.sh` одним кроком у PR-прогоні.
- `scripts/check-verified-modules.sh` — модуль мусить мати свій тест.
