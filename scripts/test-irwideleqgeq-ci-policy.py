#!/usr/bin/env python3
# G6.166 — дешевий stdlib-запобіжник дорогому SENS Rust/Zig на push/schedule.
# Статичний YAML-аудит конкретного профільного workflow, не YAML-інтерпретатор.
# Справжні ELF і семантичну правильність окремо перевіряють FPC та SENS CLI.
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/ir-wide-leqgeq.yml"
TEST = ROOT / "scripts/test-irwideleqgeq.sh"


def require(condition: bool, text: str) -> None:
    if not condition:
        raise AssertionError(text)


def verify(workflow: str, shell: str) -> None:
    """Запозичені UTF-8 тексти, лише read-only. Помилка не мутує файлові джерела.

    1. Чому невиконаний heavy job не є семантичним доказом?
    2. Чому event gate охоплює всі PR і ручні виклики?
    3. Чому native-only не може сказати oracle=16?
    4. Чому не перевіряємо семантику синтаксичним розбором YAML?
    """
    m = re.search(r"(?m)^on:\s*\n(?P<events>(?:^  [^\n]*\n|^    [^\n]*\n|^      [^\n]*\n)*)", workflow)
    require(m is not None, "немає явного YAML on: блоку")
    events = m.group("events")
    require(re.search(r"(?m)^  pull_request:\s*$", events) is not None,
            "загублено PR-тригер")
    require(re.search(r"(?m)^  workflow_dispatch:\s*$", events) is not None,
            "загублено ручний oracle")
    require(re.search(r"(?m)^  schedule:\s*$", events) is not None,
            "загублено нічний native smoke")
    require(re.search(r"(?m)^  push:", events) is None,
            "заборонено непотрібний push workflow")
    require("cron: '0 3 * * *'" in events,
            "нічна частота несподівано змінена")

    marker = "\njobs:\n  native-boundaries:\n"
    require(marker in workflow, "не знайдено швидкий FPC job")
    rest = workflow.split(marker, 1)[1]
    require("\n  oracle-parity:\n" in rest,
            "відсутній окремий незалежний oracle job")
    native, oracle = rest.split("\n  oracle-parity:\n", 1)
    require("SENS_VERIFY_MODE: native-only" in native,
            "native smoke зобов'язаний називати native-only")
    require("bash scripts/test-irwideleqgeq.sh" in native,
            "нічний smoke більше не запускає справжні ELF")
    require("scripts/test-irwideleqgeq-ci-policy.py" in native,
            "випадково обійдено тест event matrix")
    for bad in ("cargo build", "rust-toolchain", "install-zig",
                "SENS_ORACLE_BIN:", "sens-oracle/target/"):
        require(bad not in native, "нічний native job містить дорогий oracle: " + bad)

    # PR і ручна команда дозволені. Schedule не виконує незалежний oracle.
    guard = re.search(r"(?m)^    if:\s*(.+)$", oracle)
    require(guard is not None, "немає незалежного event gate дорогого job")
    allowed = guard.group(1)
    require("github.event_name == 'pull_request'" in allowed and
            "github.event_name == 'workflow_dispatch'" in allowed and
            "||" in allowed and
            "schedule" not in allowed,
            "дорогий oracle не обмежений PR та ручним запуском")
    require(re.search(r"(?m)^    needs:\s*native-boundaries\s*$", oracle) is not None,
            "oracle не залежить від позитивного машинного FPC")
    for required in ("SENS_VERIFY_MODE: full",
                     "SENS_ORACLE_BIN: ./sens-oracle/target/debug/sens",
                     "cargo build --locked -p sens-cli --bin sens",
                     "rust-toolchain",
                     "install-zig",
                     "scripts/test-irwideleqgeq.sh"):
        require(required in oracle, "PR/manual втратив повну перевірку: " + required)
    require("SENS_VERIFY_MODE: full" not in native,
            "нічний job видає себе за повний semantic oracle")

    # Shell за замовчуванням вимагає oracle. Явний обхід тільки native-only.
    for required in (
        'MODE="${SENS_VERIFY_MODE:-full}"',
        'case "$MODE" in',
        'full)',
        'native-only)',
        'test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"',
        'if [[ "$MODE" == full ]]; then',
        'test "$ORACLE_COUNT" -eq 16',
        'test "$ORACLE_COUNT" -eq 0',
        'pinned-oracle=NOT-CHECKED',
        'test "$NEG" -eq 13',
        'test "$PASS" -eq 16',
        'cmp "$TMP/cases/$label.expected.sens" "$TMP/$label.actual.sens"',
    ):
        require(required in shell, "виконавчий тест втратив перевірку: " + required)


class PolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.shell = TEST.read_text(encoding="utf-8")

    def test_current_workflow(self) -> None:
        verify(self.workflow, self.shell)

    def test_no_push_even_native(self) -> None:
        modified = self.workflow.replace("  schedule:\n", "  push:\n    branches: [main]\n  schedule:\n", 1)
        with self.assertRaisesRegex(AssertionError, "push"):
            verify(modified, self.shell)

    def test_no_rust_on_schedule(self) -> None:
        modified = self.workflow.replace("  oracle-parity:\n", "  oracle-parity:\n", 1)
        modified = modified.replace(
            "          SENS_VERIFY_MODE: native-only",
            "          SENS_VERIFY_MODE: native-only\n          # cargo build --locked",
            1,
        )
        with self.assertRaisesRegex(AssertionError, "дорогий"):
            verify(modified, self.shell)

    def test_no_unconditional_oracle(self) -> None:
        modified = self.workflow.replace(
            "    if: github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch'",
            "    if: always()", 1)
        with self.assertRaisesRegex(AssertionError, "обмежений"):
            verify(modified, self.shell)

    def test_oracle_depends_on_native(self) -> None:
        modified = self.workflow.replace("    needs: native-boundaries\n", "", 1)
        with self.assertRaisesRegex(AssertionError, "залежить"):
            verify(modified, self.shell)

    def test_oracle_not_silently_skipped_on_pr(self) -> None:
        modified = self.workflow.replace("SENS_VERIFY_MODE: full", "SENS_VERIFY_MODE: native-only", 1)
        with self.assertRaisesRegex(AssertionError, "повну перевірку"):
            verify(modified, self.shell)

    def test_no_fake_parity_on_nightly_run(self) -> None:
        modified = self.shell.replace("pinned-oracle=NOT-CHECKED", "pinned-oracle=16", 1)
        with self.assertRaisesRegex(AssertionError, "NOT-CHECKED"):
            verify(self.workflow, modified)

    def test_no_full_mode_default_bypass(self) -> None:
        modified = self.shell.replace('MODE="${SENS_VERIFY_MODE:-full}"',
                                      'MODE="${SENS_VERIFY_MODE:-native-only}"', 1)
        with self.assertRaisesRegex(AssertionError, "MODE"):
            verify(self.workflow, modified)


if __name__ == "__main__":
    unittest.main(verbosity=2)
