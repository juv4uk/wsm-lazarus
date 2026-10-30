#!/usr/bin/env python3
"""Дешевий захист PR/manual CI для справжнього Lazarus IDEIntf/WideIR.

Тестує лише host-політику GitHub Actions. Не визначає законів SENS,
не перевіряє семантику D7/D12+ і не вимірює енергію.
"""
from __future__ import annotations

import re
from pathlib import Path

WORKFLOW = (
    Path(__file__).resolve().parents[1]
    / ".github/workflows/sens-ide-ir-tree.yml"
)

WATCHED = (
    "ide/sens_ide_compiler.pas",
    "scripts/test-sens-ide-compile.lpr",
    "scripts/test-sens-ide-compile.sh",
    "scripts/test-sens-ide-ir-trigger.py",
    ".github/workflows/sens-ide-ir-tree.yml",
    "src/wsm.wideir.pas",
    "src/wsm.wideirguard.pas",
    "external/sens",
)


def need(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError("ІДЕ-CI-ВІДМОВА: " + reason)


def check_policy(source: str) -> None:
    """Точний fail-closed контроль вузького workflow без PyYAML."""
    event_block = re.search(
        r"(?ms)^on:\s*\n(.*?)(?=^[A-Za-z][\w-]*:|\Z)", source
    )
    need(event_block is not None, "немає top-level on:")
    events = re.findall(
        r"(?m)^  ([a-z_]+):[ \t]*$", event_block.group(1)
    )
    need(
        len(events) == 2
        and set(events) == {"pull_request", "workflow_dispatch"},
        "Lazarus IDEIntf/LCL має працювати лише на PR або вручну, не на push",
    )
    for watched in WATCHED:
        need(
            source.count("      - '" + watched + "'") == 1,
            "PR не відстежує обов'язковий шлях: " + watched,
        )

    for witness in (
        "run: python3 scripts/test-sens-ide-ir-trigger.py",
        "lazbuild --version",
        "fpc -iV",
        "timeout 240s bash scripts/sync-authority.sh",
        "timeout 1600s bash scripts/test-sens-ide-compile.sh",
        "scripts/test-sens-ide-compile.sh",
        "lcl-gtk2-3.0",
        "xvfb",
    ):
        need(witness in source, "вилучено чинну перевірку: " + witness)
    need(
        source.index("run: python3 scripts/test-sens-ide-ir-trigger.py")
        < source.index("timeout 240s sudo apt-get update"),
        "дешеву перевірку політики треба виконати ДО інсталяції LCL",
    )
    need(
        "runs-on: ubuntu-24.04" in source
        and "timeout-minutes: 35" in source,
        "втрачені ресурсообмеження справжнього IDE тесту",
    )
    need(
        "      - name: Отримати pinned SENS Contract 12.0" in source,
        "втрачено pinned SENS provenance",
    )


def main() -> None:
    original = WORKFLOW.read_text(encoding="utf-8")
    check_policy(original)
    mutations = {
        "повернули-пуш": original.replace(
            "  workflow_dispatch:\n", "  push:\n  workflow_dispatch:\n", 1
        ),
        "без-PR": original.replace(
            "  pull_request:\n", "  xpull_request:\n", 1
        ),
        "без-ручного-запуску": original.replace(
            "  workflow_dispatch:\n", "  xworkflow_dispatch:\n", 1
        ),
        "прибрали-сторожа": original.replace(
            "run: python3 scripts/test-sens-ide-ir-trigger.py",
            "run: echo НЕ-ПЕРЕВІРЕНО", 1
        ),
        "прибрали-PR-path": original.replace(
            "      - 'scripts/test-sens-ide-ir-trigger.py'\n", "", 1
        ),
        "без-ELF-свідка": original.replace(
            "timeout 1600s bash scripts/test-sens-ide-compile.sh",
            "echo НЕ-ВИКОНАНО", 1
        ),
        "без-піну": original.replace(
            "timeout 240s bash scripts/sync-authority.sh",
            "echo НЕ-ЗВІРЕНО", 1
        ),
        "без-Lazarus": original.replace(
            "lazbuild --version", "echo НЕМАЄ-LAZARUS", 1
        ),
        "без-FPC": original.replace("fpc -iV", "echo НЕМАЄ-FPC", 1),
    }
    for name, candidate in mutations.items():
        need(candidate != original, "не застосовано негатив: " + name)
        try:
            check_policy(candidate)
        except ValueError:
            continue
        raise ValueError("ІДЕ-CI-ВІДМОВА: мутація пройшла: " + name)
    print(
        "ІДЕ-CI-ПОЛІТИКА-ГАРАЗД PR=так manual=так push=ні "
        "negative=9 native-IDE=збережено energy=NOT-MEASURED"
    )


if __name__ == "__main__":
    main()
