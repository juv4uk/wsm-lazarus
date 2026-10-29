#!/usr/bin/env python3
"""Охоронець драбини для wsm-lazarus: індекс усіх визначень SENS.

Навіщо тут: програми пишуться в ЦЬОМУ репозиторії. Агент мусить знати,
які функції вже є в драбині д1-10, ПЕРЕД тим як писати нові. Індекс
будується з джерел SENS, а не з пам'яті.

Звідки беруться джерела: pinned external/sens (підмодуль). Якщо його не
ініціалізовано — скрипт каже це прямо, а не мовчить і не вигадує.

Вихід:
  knowledge/drabyna-index.json   машинний індекс
  knowledge/drabyna.md           людський довідник
  knowledge/drabyna-domains.md   таблиці доменів (координати)
  lib/generated/drabyna-data.lisp  дані для SENS REPL

Важливе розрізнення, яке легко згубити:
  домен — це КООРДИНАТА (таблиця lib/domains/d*.lisp), а не простір
  імен функцій. Тому «домен функції» не є властивістю функції, і цей
  скрипт його не вигадує: пише «загальна», коли префікса назви немає.
"""
import collections
import json
import pathlib
import re
import sys

DOMAIN_PREFIXES = [(f"д{n}-", f"д{n}") for n in range(12, 0, -1)]
PROJECTIONS = ["ук", "укр", "san", "en", "LISP", "sym"]


def domain_of(name: str) -> str:
    for prefix, domain in DOMAIN_PREFIXES:
        if name.startswith(prefix):
            return domain
    return "загальна"


def arity_of(text: str) -> int | None:
    """Арність із чинної форми SENS:
        (визначити ім'я (функція (параметри) тіло))
    Параметри всередині (функція ...), а не одразу після імені.
    """
    match = re.search(r"\(\s*функція\s*\(([^()]*)\)", text)
    if not match:
        return None
    body = match.group(1).strip()
    return 0 if not body else len(body.split())


def find_sens_lib(root: pathlib.Path) -> pathlib.Path | None:
    for candidate in (root / "external" / "sens" / "lib", root / "lib"):
        if (candidate / "domains").is_dir():
            return candidate
    return None


def build(root: pathlib.Path, lib: pathlib.Path) -> tuple[dict, collections.Counter, int]:
    definitions: dict[str, dict] = {}
    usage: collections.Counter = collections.Counter()
    files = sorted(lib.rglob("*.lisp"))
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        rel = str(path.relative_to(root))
        lines = text.splitlines()
        for number, line in enumerate(lines, 1):
            found = re.search(r"\(\s*визначити\s+\(?\s*([^\s()]+)", line)
            if found and found.group(1) not in definitions:
                name = found.group(1)
                arity = arity_of(line)
                if arity is None:
                    for offset in range(1, 5):
                        if number - 1 + offset >= len(lines):
                            break
                        arity = arity_of(lines[number - 1 + offset])
                        if arity is not None:
                            break
                definitions[name] = {
                    "домен": domain_of(name),
                    "файл": rel,
                    "рядок": number,
                    "арність": arity,
                }
            for token in re.findall(r"[^\s()\[\]]+", line):
                usage[token] += 1
    for name, entry in definitions.items():
        entry["уживань"] = usage[name]
    return definitions, usage, len(files)


def index_domains(root: pathlib.Path, lib: pathlib.Path) -> dict:
    result = {}
    for path in sorted((lib / "domains").glob("d*.lisp")):
        match = re.search(r"d(\d+)\.lisp$", path.name)
        if not match:
            continue
        domain = "д" + match.group(1)
        text = path.read_text(encoding="utf-8")
        coords = re.findall(r"^\s*\((\d+)\s+\(ук ", text, re.MULTILINE)
        missing = [p for p in PROJECTIONS if f"({p} " not in text]
        result[domain] = {
            "файл": str(path.relative_to(root)),
            "координат": len(coords),
            "перша": coords[0] if coords else None,
            "остання": coords[-1] if coords else None,
            "проєкцій": len(PROJECTIONS) - len(missing),
            "відсутні": missing,
        }
    return result


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    lib = find_sens_lib(root)
    if lib is None:
        print(
            "немає джерел SENS. Ініціалізуй підмодуль:\n"
            "  git submodule update --init external/sens",
            file=sys.stderr,
        )
        return 2

    definitions, _usage, file_count = build(root, lib)
    by_domain = collections.Counter(e["домен"] for e in definitions.values())
    domains = index_domains(root, lib)

    knowledge = root / "knowledge"
    knowledge.mkdir(exist_ok=True)
    (knowledge / "drabyna-index.json").write_text(
        json.dumps(
            {
                "джерело": str(lib.relative_to(root)),
                "визначень": len(definitions),
                "файлів": file_count,
                "домени": dict(sorted(by_domain.items())),
                "функції": definitions,
            },
            ensure_ascii=False,
            indent=1,
        ),
        encoding="utf-8",
    )

    top = sorted(definitions.items(), key=lambda kv: -kv[1]["уживань"])[:120]
    lines = [
        "# Драбина доменів — довідник охоронця",
        "",
        f"Джерело: `{lib.relative_to(root)}`",
        f"Визначень: **{len(definitions)}** у **{file_count}** файлах.",
        "",
        "## Скільки в кожному домені",
        "",
        "| домен | визначень |",
        "|---|---|",
    ]
    for domain, count in sorted(by_domain.items(), key=lambda kv: -kv[1]):
        lines.append(f"| {domain} | {count} |")
    lines += [
        "",
        "## Найуживаніші — на чому стоїть мова",
        "",
        "| функція | домен | уживань | де |",
        "|---|---|---|---|",
    ]
    for name, entry in top:
        lines.append(
            f"| `{name}` | {entry['домен']} | {entry['уживань']} | "
            f"{entry['файл']}:{entry['рядок']} |"
        )
    lines += [
        "",
        "## Правило для агента",
        "",
        "Перед тим як писати нову функцію — спитай охоронця, чи вона вже є.",
        "Якщо є — вживай. Якщо немає — це кандидат у д11, а не привід писати дубль.",
    ]
    (knowledge / "drabyna.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    domain_lines = [
        "# Драбина доменів — таблиці координат",
        "",
        "Домен тут — **координата**, а не простір імен функцій.",
        "Кожен рядок таблиці має шість проєкцій: ук · укр · san · en · LISP · sym.",
        "",
        "| домен | координат | проєкцій | перша | остання | файл |",
        "|---|---|---|---|---|---|",
    ]
    total = 0
    for domain, entry in sorted(domains.items(), key=lambda kv: int(kv[0][1:])):
        total += entry["координат"]
        domain_lines.append(
            f"| {domain} | {entry['координат']} | {entry['проєкцій']}/6 | "
            f"{entry['перша']} | {entry['остання']} | {entry['файл']} |"
        )
    domain_lines += ["", f"**Разом координат: {total}**"]
    (knowledge / "drabyna-domains.md").write_text(
        "\n".join(domain_lines) + "\n", encoding="utf-8"
    )

    # Дані для SENS REPL: список, а не JSON — наша мова не залежить від чужих форматів.
    out_dir = root / "lib" / "generated"
    out_dir.mkdir(parents=True, exist_ok=True)
    data = [
        "; Згенеровано scripts/drabyna-index.py — не правити руками.",
        "; (ім'я файл рядок уживань арність)",
        "",
        "(визначити (драбина-записи)",
        "  (список",
    ]
    for name, entry in sorted(definitions.items(), key=lambda kv: -kv[1]["уживань"]):
        arity = entry["арність"]
        data.append(
            f'    (список "{name}" "{entry["файл"]}" {entry["рядок"]} '
            f'{entry["уживань"]} {"()" if arity is None else arity})'
        )
    data += ["  ))"]
    (out_dir / "drabyna-data.lisp").write_text("\n".join(data) + "\n", encoding="utf-8")

    print(f"визначень: {len(definitions)} у {file_count} файлах")
    for domain, count in sorted(by_domain.items(), key=lambda kv: -kv[1]):
        print(f"  {domain}: {count}")
    for domain, entry in sorted(domains.items(), key=lambda kv: int(kv[0][1:])):
        note = "" if not entry["відсутні"] else f"  ВІДСУТНІ {entry['відсутні']}"
        print(f"  {domain}: {entry['координат']} координат, {entry['проєкцій']}/6{note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
