#!/usr/bin/env python3
"""G6.170: швидка регресія енергоощадних подій компіляторного CI.

Вхід — позичений шлях до GitHub Actions YAML; читаємо звичайний UTF-8.
Повертаємо лише локальний host-статус, а не SENS-значення/проєкцію.
Тимчасові рядки і списки — керована Python-пам'ять цього запуску.
Жодного імпорту PyYAML, мережі, Rust, Zig чи викликів мовних законів.

Питання:
  1) Чому вимкнення автоматичного oracle НЕ означає вилучення parity?
  2) Чому ручний oracle мусить залежати від успішного native?
  3) Чому відсутність push сама по собі не прибирає збірку Rust на PR?
  4) Чому мутації перевіряють політику краще за простий grep?
"""
from __future__ import annotations

import pathlib
import re
import sys

EXPECTED_PATH = pathlib.Path(".github/workflows/elf-d12-add-adaptive.yml")


def section(data: str, header: str, stop: str) -> str:
    """Повернути незмінний фрагмент між явними top-level YAML ключами."""
    start = re.search(rf"(?m)^{re.escape(header)}:\s*$", data)
    end = re.search(rf"(?m)^{re.escape(stop)}:\s*$", data)
    if start is None or end is None or end.start() <= start.end():
        return ""
    return data[start.end():end.start()]


def job(data: str, name: str) -> str:
    """Тільки двопробільний GitHub jobs.<name>, без текстових збігів у steps."""
    match = re.search(rf"(?m)^  {re.escape(name)}:\s*$", data)
    if match is None:
        return ""
    following = re.search(r"(?m)^  [a-z][a-z0-9-]*:\s*$", data[match.end():])
    if following is None:
        return data[match.end():]
    return data[match.end():match.end() + following.start()]


def verify(data: str) -> list[str]:
    """Відмова за кожної зміни event→job matrix; ніяких side effects."""
    errors: list[str] = []
    triggers = section(data, "on", "permissions")
    native = job(data, "native")
    oracle = job(data, "oracle")
    event_lines = re.findall(r"(?m)^  ([a-z_]+):\s*$", triggers)
    if sorted(event_lines) != ["pull_request", "workflow_dispatch"]:
        errors.append("тригери мають бути тільки pull_request та workflow_dispatch")
    if "    paths:" not in triggers or "elf-d12-add-adaptive.yml" not in triggers:
        errors.append("PR-маршрути фізичного компілятора втрачено")
    if not native:
        errors.append("немає автоматичного native job")
    if not oracle:
        errors.append("немає незалежного oracle job")
    if "    if: github.event_name == 'workflow_dispatch'" not in oracle:
        errors.append("дорогий SENS oracle не обмежено ручним запуском")
    if not re.search(r"(?m)^    needs:\s+native\s*$", oracle):
        errors.append("ручний oracle мусить чекати успіху native")
    if "bash scripts/test-elfd12addpotikadaptive.sh" not in native:
        errors.append("реальна FPC/ELF/T5M перевірка native втрачена")
    if "fp-compiler" not in native:
        errors.append("native не встановлює FPC")
    if "REQUIRE_SENS_ORACLE: '1'" not in oracle:
        errors.append("ручний parity має відхиляти відсутній oracle")
    if "cargo build --locked -p sens-cli --bin sens" not in oracle:
        errors.append("pinned SENS oracle збирання вилучено")
    if "ref: 2c498b35af53c085450eac6f51b87facf7f9aa47" not in oracle:
        errors.append("змінено pinned oracle authority")
    if "timeout 950s bash scripts/test-elfd12addpotikadaptive.sh" not in oracle:
        errors.append("ручний oracle не запускає наявні 16 parity")
    return errors


def selftest(data: str) -> None:
    assert verify(data) == [], "базовий workflow не пройшов політику"

    mutations = [
        ("повернення push", data.replace("  workflow_dispatch:", "  push:\n  workflow_dispatch:", 1)),
        ("втрата manual", data.replace("  workflow_dispatch:\n", "", 1)),
        ("автоматичний Rust", data.replace(
            "    if: github.event_name == 'workflow_dispatch'\n", "", 1)),
        ("відсутній native dependency", data.replace("    needs: native\n", "", 1)),
        ("прихований вимкнений oracle", data.replace(
            "REQUIRE_SENS_ORACLE: '1'", "REQUIRE_SENS_ORACLE: '0'", 1)),
        ("втрата перевірки ELF", data.replace(
            "bash scripts/test-elfd12addpotikadaptive.sh",
            "echo НЕ-ПЕРЕВІРЕНО", 1)),
        ("підміна pin", data.replace(
            "ref: 2c498b35af53c085450eac6f51b87facf7f9aa47",
            "ref: main", 1)),
    ]
    for label, mutant in mutations:
        assert mutant != data, f"зміна {label} не спрацювала"
        assert verify(mutant), f"не спіймано негатив: {label}"


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else EXPECTED_PATH
    try:
        text = path.read_text(encoding="utf-8")
        failures = verify(text)
        if failures:
            for problem in failures:
                print("ЕКОНОМНИЙ-CI-ВІДМОВА: " + problem, file=sys.stderr)
            return 2
        selftest(text)
    except (OSError, AssertionError, UnicodeError) as exc:
        print("ЕКОНОМНИЙ-CI-ПРОВАЛ: " + str(exc), file=sys.stderr)
        return 2
    print("ЕКОНОМНИЙ-CI-ГАРАЗД pr=native manual=native+oracle "
          "push=none pin=exact negatives=7 energy=NOT-MEASURED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
