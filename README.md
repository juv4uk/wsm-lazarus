# wsm-lazarus

П'ятий субстратний свідок семантичної влади [`my-lisp`](https://github.com/juv4uk/my-lisp),
реалізований на **Free Pascal / Lazarus (FPC/LCL)**.

Одна семантика — різні субстрати:

| Субстрат | Роль |
|---|---|
| Rust | Reference surface майбутнього |
| Graal (Java) | Перший канон-свідок `wsm-graalvm` |
| WASM/C / FPGA | Експериментальні лінії lowered semantics |
| **FPC (цей репо)** | Нативний детермінований свідок + (M2) LCL GUI-інспектор |

## Критерій M0 — буквально той самий

```
(canon-conforms?) → t
```

з pinned `external/my-lisp/lib/canon.lisp`. Свідок згоден із контрактом;
субстрат не має влади над семантикою.

## Споріднені репозиторії

- `juv4uk/my-lisp` — semantic authority (pin fa9bd8757…)
- `juv4uk/wsm-graalvm` — JVM/native-image свідок, еталон гейтів для цього репо

## Ліцензія

ВОЛЬНІСТЬ (див. `LICENSE`).

## Стан

Запущено 2026-09-18. Дивись `docs/decisions/` та `tasks`.