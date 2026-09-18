# wsm-lazarus

П'ятий субстратний свідок семантичної влади [`my-lisp`](https://github.com/juv4uk/my-lisp),
реалізований на **Free Pascal / Lazarus (FPC/LCL)**.

Одна семантика — різні субстрати:

| Субстрат | Роль |
|---|---|
| Rust | Reference surface майбутнього |
| Graal (Java) | Перший канон-свідок `wsm-graalvm` |
| WASM/C / FPGA | Експериментальні лінії lowered semantics |
| **FPC (цей repo)** | Нативний детермінований свідок + (M2) LCL GUI-інспектор |

## Критерій M0

Критерій не задається цим repo і не успадковується зі старого Graal wording.
Він читається з pinned `external/my-lisp/lib/canon.lisp`.

Для pin `fa9bd8757983eb0eb8b3228c56ccc53471adde0c` canonical self-verdict є:

```lisp
(canon-conforms?) ; => (canon-conformance satisfied)
```

Тобто FPC-свідок має відтворити **саме pinned result record**, а не локальний
boolean shortcut. Субстрат не має влади над семантикою.

## Споріднені репозиторії

- `juv4uk/my-lisp` — semantic authority (pin `fa9bd8757…`)
- `juv4uk/wsm-graalvm` — інший substrate witness; корисний як engineering reference,
  але не як semantic authority для FPC

## Ліцензія

ВОЛЬНІСТЬ (див. `LICENSE`).

## Guix

```bash
# скороминучий dev-shell
guix shell -m manifest.scm
# постійний профіль (fpc + git + make + coreutils)
guix package -p ~/.guix-profiles/wsm-lazarus -m \
  /tmp/opencode/min-manifest.scm   # або відредагований manifest.scm без lazarus
```

`manifest.scm` декларує також `lazarus` (LCL-інспектор, M2) — він не входить
в активний профіль до М2 (замикання qt +~925MB).

## Стан

Запущено 2026-09-18. Вертикалі: `tasks.lisp`. Рішення: `docs/decisions/`.
Перші рубежі (M0): CLEAN → PIN → HEADLESS → VALUES → READER → ID → EVAL →
MECHANISM → CANON.
