#!/usr/bin/env python3
"""G6.165 — швидка stdlib-перевірка подієвого бюджету CI, без Rust/Zig.

Типи: UTF-8 YAML source як str; steps — str->str зі смугами кроків.
Параметри: лише path до цього репозиторію; жодного мережевого виклику.
Пам'ять: локальні рядки/словники Python, живуть до завершення процесу.
Результат: 0+доказ PASS або 1+діагностика; жодного SENS dispatch.

Питання:
1. Чому nightly FPC не має вимагати nightly Rust і Zig?
2. Чому PR семантичний oracle повинен залишатися обов'язковим?
3. Чому відхилення не можна маскувати як SUCCESS?
4. Чим YAML workflow відрізняється від канонічного binary .sens?
5. Для чого негативно мутувати кожний guard, а не тільки читати YAML?
"""
from pathlib import Path
import re
import sys

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/ir-wide-front-d6-kroky.yml"
GUARD = "if: ${{ github.event_name != 'schedule' }}"
ORACLE_STEPS = (
    "Отримати незалежний pinned SENS",
    "dtolnay/rust-toolchain@1.99.0",
    "./sens-oracle/.github/actions/install-zig",
    "Зібрати незалежний SENS CLI точного pinned SHA",
    "Вимагати byte-parity SENS REPL для кожної фізичної програми",
)
NATIVE = "Перевірити FPC і 64 справжні ELF64 перед незалежним оракулом"


class BudgetViolation(ValueError):
    """Порушення перевірюваного CI-контракту."""


def require(ok: bool, message: str) -> None:
    if not ok:
        raise BudgetViolation(message)


def extract_steps(content: str) -> dict[str, str]:
    """Без YAML-залежностей: читати лише кроки з точним відступом GitHub job."""
    lines = content.splitlines()
    starts = [i for i, line in enumerate(lines) if re.match(r"^      - (?:name|uses): ", line)]
    require(bool(starts), "немає жодного job step")
    parts: dict[str, str] = {}
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(lines)
        first = lines[start].split(": ", 1)[1].strip()
        require(first not in parts, "дубльований step: " + first)
        parts[first] = "\n".join(lines[start:end])
    return parts


def verify(content: str) -> None:
    """Перевірити цілісний YAML event/step контракт; без моделювання SENS."""
    require(re.search(r"(?m)^on:\s*$", content) is not None, "немає events")
    for event in ("pull_request", "schedule", "workflow_dispatch"):
        require(re.search(r"(?m)^  " + event + r":\s*$", content) is not None, "немає "+event)
    require(re.search(r"(?m)^  push:\s*$", content) is None, "важкий D6 job не можна повертати на push")
    # Чинний нічний механічний D6-gate запускається о 04:00 UTC; не розширювати бюджет.
    require("cron: '0 4 * * *'" in content, "нічний бюджет/розклад змінено")
    require("ref: 1f1bf676eeac605e065035d9dd2adaae807f1788" in content,
            "змінено pinned SENS semantic authority")
    require("scripts/test-irwidefront-d6-kroky.sh" in content, "втрачено тест ELF64")
    require("SENS_ORACLE_BIN: ./sens-oracle/target/debug/sens" in content,
            "втрачено незалежний oracle binary")
    require("cargo build --locked -p sens-cli --bin sens" in content,
            "втрачено real oracle build")
    require("timeout 900s bash scripts/test-irwidefront-d6-kroky.sh" in content,
            "втрачено byte parity test")
    steps = extract_steps(content)
    for name in ORACLE_STEPS:
        require(name in steps, "бракує oracle step: "+name)
        body = steps[name]
        require(re.search(r"(?m)^        if: ", body) is not None, "немає guard: "+name)
        require("        " + GUARD in body, "неправильний guard: "+name)
        require(len(re.findall(r"(?m)^        if: ", body)) == 1, "неоднозначний guard: "+name)
    for name in (NATIVE, "Встановити Free Pascal і машинні перевіряльники"):
        require(name in steps, "втрачено нативний step: "+name)
        require(re.search(r"(?m)^        if: ", steps[name]) is None,
                "FPC/ELF gate помилково вимкнено: "+name)
    require("timeout 600s bash scripts/test-irwidefront-d6-kroky.sh" in steps[NATIVE],
            "забрано 64 real FPC/ELF tests")
    require("timeout 10s python3 scripts/test-ir-wide-d6-ci-policy.py" in content,
            "самоперевірку політики не включено у CI")
    # Тільки schedule пропускає п'ять oracle кроків; PR/manual їх усі виконують.
    for event in ("schedule", "pull_request", "workflow_dispatch"):
        oracle = event != "schedule"
        actual = all((event != "schedule") for _ in ORACLE_STEPS)
        require(actual == oracle, "неузгоджена подієва матриця")


def mutation_tests(content: str) -> int:
    tests = []
    for name in ORACLE_STEPS:
        block = extract_steps(content)[name]
        # if може бути останнім рядком action-step: видаляємо сам guard,
        # незалежно від завершального LF; решту YAML залишаємо незмінною.
        damaged = block.replace("        "+GUARD, "", 1)
        require(damaged != block, "немає guard для мутації "+name)
        tests.append(content.replace(block, damaged, 1))
    native = extract_steps(content)[NATIVE]
    tests.append(content.replace(native, native.replace("\n", "\n        "+GUARD+"\n", 1), 1))
    tests.append(content.replace("  schedule:", "  push:", 1))
    tests.append(content.replace("  workflow_dispatch:", "  unavailable:", 1))
    tests.append(content.replace("cargo build --locked -p sens-cli --bin sens", "echo mock-oracle", 1))
    tests.append(content.replace("timeout 600s bash scripts/test-irwidefront-d6-kroky.sh",
                                 "echo mock-native", 1))
    tests.append(content.replace("ref: 1f1bf676eeac605e065035d9dd2adaae807f1788",
                                 "ref: main", 1))
    for index, damaged in enumerate(tests, 1):
        require(damaged != content, "неподіяла негативна мутація "+str(index))
        try:
            verify(damaged)
        except BudgetViolation:
            continue
        raise BudgetViolation("не відхилена негативна мутація "+str(index))
    return len(tests)


def main() -> int:
    try:
        source = WORKFLOW.read_text(encoding="utf-8")
        verify(source)
        count = mutation_tests(source)
    except (BudgetViolation, OSError) as error:
        print("ПОЛІТИКА-D6-ВІДМОВА: "+str(error), file=sys.stderr)
        return 1
    print(f"ПОЛІТИКА-D6-PASS schedule=native-only pr=oracle manual=oracle negative={count} heavy-push=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
