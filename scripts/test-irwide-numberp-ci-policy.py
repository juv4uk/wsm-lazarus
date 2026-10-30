#!/usr/bin/env python3
"""G6.169: доказ подієвого бюджету CI без сторонніх залежностей.

Цей тест перевіряє YAML-маршрутизацію, а не семантику SENS або
вимірювання джоулів. Справжні FPC/ELF та pinned SENS oracle
залишаються окремими обов'язковими кроками workflow.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/irwide-numberp.yml"
SCRIPT = ROOT / "scripts/test-irwidenumberp.sh"
GUARD = "if: ${{ github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch' }}"
EVENTS = ("pull_request:", "schedule:", "workflow_dispatch:")


def verify(source: str, script: str) -> None:
    """Borrowed UTF-8 YAML і shell; виняток означає fail-closed.

    Пам'ять: лише тимчасові Python str; жодної інтерпретації SENS.
    Результат: None при успіху, AssertionError для хибної політики.
    1) Чому нічний schedule може пройти без Rust/Zig, але PR — ні?
    2) Чому 'needs: native' не дозволяє витрачати oracle CPU після RED?
    3) Чому тест не підміняє живу перевірку pinned SENS?
    4) Чому додавання push-тригера є регресією бюджетної політики?
    """
    lines = source.splitlines()
    def section(start: str, end: str | None = None) -> str:
        assert start in lines, f"немає розділу {start}"
        idx = lines.index(start)
        stop = lines.index(end, idx + 1) if end else len(lines)
        return "\n".join(lines[idx + 1:stop])

    event_section = section("on:", "permissions:")
    event_lines = [
        line.strip() for line in event_section.splitlines()
        if line.startswith("  ") and not line.startswith("    ")
    ]
    for event in EVENTS:
        assert event in event_lines, f"втрачено подію {event}"
    assert "push:" not in event_lines, "заборонено важкий запуск на кожний push"
    assert "cron: '20 3 * * *'" in event_section, "нічний графік змінено"
    assert "'scripts/test-irwide-numberp-ci-policy.py'" in event_section, (
        "політика не запускається при її зміні"
    )

    native = section("  native:", "  oracle:")
    oracle = section("  oracle:")
    assert "runs-on: ubuntu-24.04" in native and "runs-on: ubuntu-24.04" in oracle
    assert "timeout 12s python3 scripts/test-irwide-numberp-ci-policy.py" in native
    assert "timeout 480s bash ./scripts/test-irwidenumberp.sh" in native
    assert "fp-compiler binutils git" in native, "втрачено FPC машинні перевірки"
    assert "cargo build" not in native and "rust-toolchain" not in native, (
        "важкий Rust у швидкому FPC job"
    )
    assert "install-zig" not in native and "sens-oracle" not in native, (
        "важкий pinned oracle у швидкому FPC job"
    )

    oracle_lines = [line.strip() for line in oracle.splitlines()]
    assert GUARD in oracle_lines, "дорогий oracle дозволено поза PR/manual"
    assert "needs: native" in oracle_lines, "дорогий oracle не залежить від PASS native"
    assert "repository: juv4uk/sens" in oracle
    assert "ref: 1f1bf676eeac605e065035d9dd2adaae807f1788" in oracle
    assert "dtolnay/rust-toolchain@1.99.0" in oracle
    assert "./sens-oracle/.github/actions/install-zig" in oracle
    assert "cargo build --locked -p sens-cli --bin sens" in oracle
    assert "REQUIRE_SENS_ORACLE: '1'" in oracle
    assert "timeout 480s bash ./scripts/test-irwidenumberp.sh" in oracle
    assert 'energy=NOT-MEASURED' in script
    assert 'test "$PASS" -eq 17' in script
    assert 'test "$NEG" -eq 22' in script
    assert "cmp \"$TMP/$tag.expected.oracle\" \"$TMP/$tag.oracle\"" in script


def main() -> None:
    """Усі мутації знищують реальний gate, а не лише коментарі."""
    workflow = WORKFLOW.read_text(encoding="utf-8")
    script = SCRIPT.read_text(encoding="utf-8")
    verify(workflow, script)
    attacks = (
        (workflow.replace(GUARD, "if: ${{ github.event_name != 'push' }}"), script),
        (workflow.replace(GUARD, ""), script),
        (workflow.replace("needs: native", "needs: nothing"), script),
        (workflow.replace("  workflow_dispatch:", "  push:"), script),
        (workflow.replace("  pull_request:", "  push:"), script),
        (workflow.replace("    - cron: '20 3 * * *'", "    - cron: '0 * * * *'"), script),
        (workflow.replace("timeout 12s python3 scripts/test-irwide-numberp-ci-policy.py", "echo skipped"), script),
        (workflow.replace("timeout 480s bash ./scripts/test-irwidenumberp.sh", "echo skipped"), script),
        (workflow.replace("REQUIRE_SENS_ORACLE: '1'", "REQUIRE_SENS_ORACLE: '0'"), script),
        (workflow.replace("cargo build --locked -p sens-cli --bin sens", "true"), script),
        (workflow.replace("ref: 1f1bf676eeac605e065035d9dd2adaae807f1788", "ref: main"), script),
        (workflow, script.replace('test "$NEG" -eq 22', "true")),
        (workflow, script.replace('test "$PASS" -eq 17', "true")),
    )
    for index, (bad_workflow, bad_script) in enumerate(attacks, 1):
        assert (bad_workflow, bad_script) != (workflow, script), (
            f"мутація {index} не застосована"
        )
        try:
            verify(bad_workflow, bad_script)
        except AssertionError:
            continue
        raise AssertionError(f"пропущено небезпечну мутацію #{index}")
    print(
        "G6.169-ПОЛІТИКА-ГАРАЗД події=3 нічний=FPC "
        "PR=FPC+oracle ручний=FPC+oracle "
        f"негативні-мутації={len(attacks)} енергія=НЕ-ВИМІРЯНО"
    )


if __name__ == "__main__":
    main()
