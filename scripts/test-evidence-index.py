#!/usr/bin/env python3
"""G0.1: механічна цілісність ДОКАЗІВ, не оракул SENS.
Перевіряємо реальні шляхи таблиці, pinned authority й межу тверджень.
Усі нормативні закони лишаються ТІЛЬКИ в juv4uk/sens.
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

PIN_RE = re.compile(r"^MY_LISP_PIN=([0-9a-f]{40})$", re.MULTILINE)
LINK_RE = re.compile(r"(?<!!)\[[^\]\n]+\]\(([^)]+)\)")
CODE_RE = re.compile(r"`((?:src|scripts|docs|evidence|refs|gui|\.github|external/sens)/[^\s`]+)`")
DOCUMENTS = ("AGENTS.md", "README.md", "docs/native-system-roadmap.uk.md")
SOURCES = ("README.md", "docs/native-system-roadmap.uk.md")
MIN_PROOFS = 5


class ProofError(Exception):
    """Явна відмова, без часткового PASS."""


def require(condition: bool, detail: str) -> None:
    if not condition:
        raise ProofError(detail)


def pinned(root: pathlib.Path) -> str:
    baseline = root / "refs/tier1-baseline.properties"
    require(baseline.is_file(), "немає чинного файлу pinned SHA")
    data = baseline.read_text(encoding="utf-8")
    hits = PIN_RE.findall(data)
    require(len(hits) == 1, "неоднозначний pinned SENS SHA")
    return hits[0]


def check_path(root: pathlib.Path, doc: pathlib.Path, reference: str) -> None:
    # URL, mailto та внутрішній заголовок не є репозиторними шляхами.
    value = reference.strip().split(" ", 1)[0]
    if not value or value.startswith("#"):
        return
    url = urlsplit(value)
    if url.scheme or url.netloc:
        return
    path = unquote(url.path)
    if not path:
        return
    require(not path.startswith("/"), f"{doc}: абсолютний внутрішній шлях: {path}")
    require("\\x00" not in path and "\\\\" not in path,
            f"{doc}: заборонений фізичний шлях: {path}")
    target = (doc.parent / path).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError as error:
        raise ProofError(f"{doc}: вихід за межі репозиторію: {path}") from error
    require(target.exists(), f"{doc}: відсутній матеріальний доказ: {path}")


def validate(root: pathlib.Path, check_gitlink: bool = False) -> tuple[int, int]:
    root = root.resolve()
    pin = pinned(root)
    inspected = 0
    tables = 0
    for name in DOCUMENTS:
        doc = root / name
        require(doc.is_file(), f"немає обов'язкового документа {name}")
        text = doc.read_text(encoding="utf-8")
        require(pin in text, f"{name}: мовний authority pin відрізняється від baseline")
        require("12.0" in text, f"{name}: немає чинного Contract 12.0")
        if name in SOURCES:
            # У таблиці має бути не лише посилання, а й явне обмеження доказу.
            in_proofs = False
            rows = 0
            for line in text.splitlines():
                cells = [x.strip() for x in line.split("|")[1:-1]] if line.startswith("|") and line.endswith("|") else []
                if len(cells) >= 3 and (
                    "Межа доказу" in cells[2] or "Чого це" in cells[2]
                ):
                    in_proofs = True
                    continue
                if not in_proofs:
                    continue
                if not cells:
                    in_proofs = False
                    continue
                if all(set(x) <= set("-: ") for x in cells):
                    continue
                require(len(cells) >= 3, f"{name}: втрачено колонку меж доказу")
                require(len(cells[1]) >= 12, f"{name}: порожній матеріальний доказ")
                require(len(cells[2]) >= 12, f"{name}: порожнє «чого не доводить»")
                rows += 1
            require(rows >= MIN_PROOFS, f"{name}: замало фізичних рядків доказів ({rows})")
            tables += rows
        for entry in LINK_RE.findall(text):
            check_path(root, doc, entry)
            inspected += 1
        for entry in CODE_RE.findall(text):
            # Файлові шаблони та виклики з додатковими токенами — не конкретні файли.
            if any(ch in entry for ch in "*?{}<>"):
                continue
            # Тільки самодостатні локальні шляхи, не фрагменти речень.
            entry = entry.rstrip(".,;:")
            check_path(root, root / ".", entry)
            inspected += 1

    if check_gitlink:
        expected = subprocess.run(
            ["git", "ls-tree", "HEAD", "external/sens"],
            cwd=root, capture_output=True, text=True, check=True
        ).stdout.strip()
        require(expected.startswith("160000 commit " + pin + "\t"),
                "gitlink external/sens не відповідає документації")
        require((root / "external/sens/contracts/language-contract-12.lisp").is_file(),
                "не матеріалізовано закріплений Contract 12")
    return inspected, tables


def selftest() -> None:
    """Незалежні негативи без потреби писати в реальний checkout."""
    with tempfile.TemporaryDirectory(prefix="dokazy-") as home:
        root = pathlib.Path(home)
        (root / "refs").mkdir()
        (root / "docs").mkdir()
        (root / "scripts").mkdir()
        pin = "a" * 40
        (root / "refs/tier1-baseline.properties").write_text(
            "MY_LISP_PIN=" + pin + "\n", encoding="utf-8"
        )
        (root / "scripts/evidence.sh").write_text("test", encoding="utf-8")
        table = (
            "| Частина | Доказ | Межа доказу |\n"
            "| --- | --- | --- |\n" +
            "| X | [доказ](scripts/evidence.sh) | Не доводить повного виконання |\n" * 5
        )
        (root / "AGENTS.md").write_text(pin + " Contract 12.0", encoding="utf-8")
        (root / "README.md").write_text(pin + " Contract 12.0\n" + table,
                                        encoding="utf-8")
        # Для docs/ відносний доказ треба дійсно шукати у ../scripts.
        roadmap_table = table.replace("](scripts/", "](../scripts/")
        (root / "docs/native-system-roadmap.uk.md").write_text(
            pin + " Contract 12.0\n" + roadmap_table, encoding="utf-8"
        )
        validate(root)
        def rejects(label: str) -> None:
            try:
                validate(root)
            except ProofError:
                return
            raise AssertionError("пропущено негатив: " + label)
        doc = root / "README.md"
        original = doc.read_text(encoding="utf-8")
        doc.write_text(original.replace("scripts/evidence.sh", "scripts/nope.sh"))
        rejects("missing file")
        doc.write_text(original.replace("scripts/evidence.sh", "../outside.md"))
        rejects("path escape")
        doc.write_text(original.replace(pin, "b" * 40))
        rejects("pin drift")
        doc.write_text(original.replace("Не доводить повного виконання", ""))
        rejects("missing limit")
        doc.write_text(original, encoding="utf-8")
        validate(root)
    print("ДОКАЗИ-САМОПЕРЕВІРКА-ГАРАЗД missing=відмова escape=відмова pin=відмова межі=відмова")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--самоперевірка":
            selftest()
        elif len(sys.argv) == 1:
            location = pathlib.Path(__file__).resolve().parent.parent
            paths, rows = validate(location, check_gitlink=True)
            print(f"ДОКАЗИ-ЦІЛІСНІСТЬ-ГАРАЗД перевірено-шляхів={paths} "
                  f"рядків={rows} pin=так Contract12=так")
        else:
            raise ProofError("очікується відсутність параметрів або --самоперевірка")
    except (ProofError, OSError, UnicodeError, subprocess.CalledProcessError) as exc:
        print(f"ДОКАЗИ-ЦІЛІСНІСТЬ-ПРОВАЛ: {exc}", file=sys.stderr)
        sys.exit(1)
