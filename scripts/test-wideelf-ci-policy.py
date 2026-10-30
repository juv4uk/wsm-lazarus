#!/usr/bin/env python3
"""Дешевий охоронець матриці GitHub Actions для нативного компілятора.

Вхід — YAML-текст workflow, результат — відмова або OK без файлових змін.
Це не обчислювач SENS та не вимірювання джоулів.
Питання: чому PR-оракул обов'язковий; чому нічний native не можна
пропускати; навіщо зберігати ручний повний прогін; що саме не виміряно?
"""
from __future__ import annotations

import re
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[1] / (
    ".github/workflows/wideelf-vidtvoriuvanist.yml"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError("CI-ВАГА-ВІДМОВА: " + message)


def check_policy(source: str) -> None:
    """Перевіряє події та jobs без залежності від PyYAML або Rust/Zig."""
    events = set(re.findall(
        r"(?m)^  (pull_request|push|schedule|workflow_dispatch):\s*$",
        source,
    ))
    require(events == {"pull_request", "schedule", "workflow_dispatch"},
            "мають лишитися PR, нічний schedule і ручний запуск; жодного push")
    require(re.search(
        r"(?m)^  schedule:\s*\n    - cron: '0 3 \* \* \*'\s*$", source,
    ) is not None, "змінено чинний нічний розклад")
    native = re.search(r"(?ms)^  native:\n(.*?)(?=^  oracle:|\Z)", source)
    oracle = re.search(r"(?ms)^  oracle:\n(.*?)(?=^  [a-zA-Z_-]+:|\Z)", source)
    require(native is not None and oracle is not None,
            "потрібні обидва jobs: native та oracle")
    native_body = native.group(1)
    oracle_body = oracle.group(1)
    require(re.search(r"(?m)^    if:", native_body) is None,
            "нічний native job не повинен мати умови пропуску")
    require(re.search(
        r"(?m)^    if: github\.event_name != 'schedule'\s*$",
        oracle_body,
    ) is not None, "дорогий oracle не повинен запускатись щоночі")
    for heavy in ("rust-toolchain@", "install-zig", "cargo build --locked"):
        require(heavy not in native_body and heavy in oracle_body,
                "важка збірка має лишатися тільки в PR/manual oracle: " + heavy)
    require("REQUIRE_SENS_ORACLE: '1'" in oracle_body,
            "на PR oracle parity має лишатися обов'язковим")
    require("test-wideelf-vidtvoriuvanist.sh" in native_body
            and "test-wideelf-vidtvoriuvanist.sh" in oracle_body,
            "44 native ELF та 22 oracle не можна вилучати з тестів")
    require("test-wideelf-ci-policy.py" in native_body,
            "дешевий policy-тест повинен запускатись до FPC")
    for watched in (
        "scripts/test-wideelf-vidtvoriuvanist.sh",
        "scripts/test-wideelf-ci-policy.py",
        ".github/workflows/wideelf-vidtvoriuvanist.yml",
    ):
        require(source.count("- '" + watched + "'") == 1,
                "PR paths повинен спостерігати: " + watched)


def main() -> None:
    original = WORKFLOW.read_text(encoding="utf-8")
    check_policy(original)
    mutations = {
        "приховано-оракул-із-PR": original.replace(
            "    if: github.event_name != 'schedule'\n",
            "    if: github.event_name == 'workflow_dispatch'\n", 1),
        "нічний-Rust": original.replace(
            "    if: github.event_name != 'schedule'\n", "", 1),
        "повернули-push": original.replace(
            "  workflow_dispatch:\n", "  push:\n  workflow_dispatch:\n", 1),
        "немає-PR": original.replace(
            "  pull_request:\n", "  xpull_request:\n", 1),
        "оракул-необовязковий": original.replace(
            "REQUIRE_SENS_ORACLE: '1'",
            "REQUIRE_SENS_ORACLE: '0'", 1),
        "важкий-Rust-у-native": original.replace(
            "  native:\n", "  native:\n    # cargo build --locked\n", 1),
    }
    for name, changed in mutations.items():
        require(changed != original, "негативна мутація не застосувалась: " + name)
        try:
            check_policy(changed)
        except ValueError:
            continue
        raise ValueError("CI-ВАГА-ВІДМОВА: мутація пройшла: " + name)
    print("CI-ВАГА-ГАРАЗД PR=native+oracle schedule=native-only "
          "manual=native+oracle push=forbidden mutations=6 energy=NOT-MEASURED")


if __name__ == "__main__":
    main()
