#!/usr/bin/env python3
"""G6.172. Механічний захист недорогого push CI, не мовний оракул SENS.

Вхід: borrowed робоче дерево .github/workflows; усі UTF-8 .yml/.yaml.
Результат: тільки host-діагностика і exit(0/1), без мережі та компіляції.
Структурно читаємо ЛИШЕ верхній ключ YAML on: і його прямі події.
Невідоме inline-значення, дубль або відсутність on: → fail closed.
Ніяких змін pinned SENS, T5M, D7, D12+ чи compiler/runtime laws.

Питання: чому 1 push-робота краще за 192? Чому коментар про push не
є тригером? Чому опт-in PR/manual oracle не треба відключати?
Чому невідоме YAML представлення має провалити guard, а не дозволити push?
Кому належать bytes прочитаних workflow? Python звільняє їх після scan.
"""
import argparse
import re
import sys
import tempfile
from pathlib import Path

ALLOWED_PUSH = frozenset({"core1-repl.yml"})
ROOT_ON = re.compile(r"^(?:on|'on'|\"on\"):\s*(.*)$")
TOP = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*\s*:")
EVENT = re.compile(r"^  (?:['\"]?)([A-Za-z_][A-Za-z0-9_-]*)(?:['\"]?)\s*:")
HEAVY = re.compile(
    r"\b(?:cargo\s+(?:build|test|run)|rustc\b|"
    r"zig\s+(?:build|test|run)|go\s+(?:build|test)|"
    r"mvn\b|gradle\b|dotnet\s+build|npm\s+(?:ci|install)|"
    r"rust-toolchain|install-zig)\b", re.IGNORECASE
)


class PolicyError(Exception):
    """Помилка host-політики, не SENS-предикат D1."""


def events(source: str, filename: str) -> tuple[set[str], dict[str, str]]:
    """Виділяє тільки top-level YAML on; indent 2 = назва події."""
    block: list[str] = []
    inline = None
    found = False
    active = False
    for line in source.splitlines():
        if "\t" in line[:len(line) - len(line.lstrip(" \t"))]:
            raise PolicyError(f"{filename}: YAML-відступ містить TAB")
        line = line.rstrip()
        bare = line.lstrip()
        if not bare or bare.startswith("#"):
            continue
        if line == bare:  # новий верхній ключ
            match = ROOT_ON.fullmatch(line)
            active = match is not None
            if active:
                if found:
                    raise PolicyError(f"{filename}: повторений верхній on:")
                found = True
                inline = match.group(1).split(" #", 1)[0].strip()
                if inline and not (
                    inline.startswith("[") or inline.startswith("{")
                    or re.fullmatch(r"['\"]?[A-Za-z_][A-Za-z0-9_-]*['\"]?", inline)
                ):
                    raise PolicyError(f"{filename}: невідоме inline on:")
            elif not TOP.match(line):
                # Непізнаний верхній синтаксис у ділянці event triggers.
                pass
        elif active:
            block.append(line)
    if not found:
        raise PolicyError(f"{filename}: немає верхнього on:")
    found_events: set[str] = set()
    by_event: dict[str, str] = {}
    if inline:
        tokens = re.findall(r"\b(?:push|pull_request|workflow_dispatch|"
                            r"schedule|workflow_call|release|issues|"
                            r"pull_request_target)\b", inline)
        found_events.update(tokens)
        if not tokens:
            raise PolicyError(f"{filename}: порожній/невідомий inline on")
        if "push" in tokens:
            by_event["push"] = inline
    else:
        current = None
        for line in block:
            m = EVENT.match(line)
            if m:
                current = m.group(1)
                found_events.add(current)
                by_event[current] = line + "\n"
            elif line.startswith("  - "):
                item = line[4:].strip().strip("'\"")
                if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", item):
                    raise PolicyError(f"{filename}: непрозорий on-список")
                current = item
                found_events.add(item)
                by_event.setdefault(item, "")
            elif current:
                by_event[current] += line + "\n"
            elif line.startswith(" ") and line.strip():
                raise PolicyError(f"{filename}: неоднозначна YAML-подія")
    if not found_events:
        raise PolicyError(f"{filename}: порожній список подій")
    return found_events, by_event


def inspect(path: Path) -> tuple[bool, int]:
    text = path.read_text(encoding="utf-8")
    found, sections = events(text, path.name)
    if "push" not in found:
        return False, 0
    if path.name not in ALLOWED_PUSH:
        raise PolicyError(f"{path.name}: push заборонений: лише {sorted(ALLOWED_PUSH)}")
    push = sections["push"]
    if not re.search(r"(?m)^    branches:\s*\[main\]\s*$", push):
        raise PolicyError(f"{path.name}: push не обмежений main")
    if not re.search(r"(?m)^    paths:\s*$", push):
        raise PolicyError(f"{path.name}: push не обмежений paths")
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        if HEAVY.search(line):
            raise PolicyError(f"{path.name}: важкий компілятор у push workflow: {line.strip()}")
    return True, 0


def audit(directory: Path) -> tuple[int, int]:
    if not directory.is_dir():
        raise PolicyError("немає каталогу .github/workflows")
    paths = sorted(p for p in directory.iterdir()
                   if p.is_file() and p.suffix in (".yml", ".yaml"))
    if not paths:
        raise PolicyError("немає workflow для аудиту")
    pushes = 0
    for path in paths:
        has_push, _ = inspect(path)
        pushes += int(has_push)
    if pushes > len(ALLOWED_PUSH):
        raise PolicyError("більше одного дорогого push workflow")
    return len(paths), pushes


def selftest() -> int:
    """Мутації policy-test, щоб тест НЕ міг зеленіти від no-op guard."""
    good = (
        "name: Легкий Core1\n"
        "on:\n"
        "  pull_request:\n"
        "  push:\n"
        "    branches: [main]\n"
        "    paths:\n"
        "      - 'src/senscore1repl.lpr'\n"
        "jobs:\n"
        "  cheap:\n"
        "    runs-on: ubuntu-24.04\n"
        "    steps:\n"
        "      - run: fpc -iV\n"
    )
    cases = 0
    with tempfile.TemporaryDirectory(prefix="sens-ci-policy-") as t:
        folder = Path(t)
        main = folder / "core1-repl.yml"
        other = folder / "other.yml"
        def check(source: str, filename: Path, expected: bool) -> None:
            nonlocal cases
            filename.write_text(source, encoding="utf-8")
            try:
                audit(folder)
                valid = True
            except PolicyError:
                valid = False
            if valid != expected:
                raise AssertionError(f"policy-case {cases+1} {filename.name}: {valid}")
            cases += 1
        check(good, main, True)
        check("name: Лише PR\non:\n  pull_request:\n", other, True)
        check(good.replace("fpc -iV", "cargo build --locked"), main, False)
        check(good.replace("fpc -iV", "zig build"), main, False)
        check(good.replace("branches: [main]", "branches: [dev]"), main, False)
        check(good.replace("    paths:\n", ""), main, False)
        check(good, main, True)
        check("on:\n  push:\n    branches: [main]\n    paths:\n      - 'x'\n", other, False)
        check("on: [push, workflow_dispatch]\n", other, False)
        check('\"on\": {push: {branches: [main]}}\n', other, False)
        check("# on: push\nname: немає event\n", other, False)
        check("on:\n  pull_request:\n# push:\n", other, True)
        check("on:\n  pull_request:\n  schedule:\n    - cron: '0 2 * * *'\n", other, True)
        check("on:\n  pull_request:\n\non:\n  push:\n", other, False)
        check("on:\n  pull_request:\n  push:\n    branches: [main]\n    paths:\n      - 'x'\n", other, False)
        check("on:\n  pull_request:\n", other, True)
        # Регресія G6.174: PR і нічний FPC не повинні повертати push
        # до дорогого Rust/Zig-оракула іншої роботи.
        check(
            "name: Парний stdin\non:\n  pull_request:\n  schedule:\n"
            "    - cron: '15 4 * * *'\n  workflow_dispatch:\n",
            other, True,
        )
        check(
            "name: Парний stdin\non:\n  pull_request:\n  push:\n"
            "    branches: [main]\n    paths:\n"
            "      - 'scripts/test-parstdinelf.sh'\n"
            "  schedule:\n    - cron: '15 4 * * *'\n"
            "  workflow_dispatch:\n",
            other, False,
        )
    return cases


def main() -> int:
    parser = argparse.ArgumentParser(description="Енергоощадний допуск CI для SENS")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    try:
        if args.selftest:
            n = selftest()
            print(f"ЕНЕРГО-CI-САМОТЕСТ-ГАРАЗД негативи-і-позитиви={n}")
            return 0
        count, push = audit(Path(args.root) / ".github" / "workflows")
        print(f"ЕНЕРГО-CI-ГАРАЗД workflows={count} push={push} rust-zig-push=0")
        return 0
    except (PolicyError, UnicodeError, OSError, AssertionError) as exc:
        print(f"ЕНЕРГО-CI-ВІДМОВА: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
