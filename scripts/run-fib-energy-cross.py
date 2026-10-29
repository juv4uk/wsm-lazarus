#!/usr/bin/env python3
"""G6.138: міжмовний лічильник енергії CPU package (не SENS семантика).

Лише Linux powercap package-level energy_uj + max_energy_range_uj.
Кожне виконання перевіряється за exit-code ДО публікації результатів.
Тестовий root завжди позначено SIMULATED. Жодних обчислених джоулів,
коли реальний RAPL недоступний. Підтримано максимум ОДИН wrap за запуск.
"""
import argparse
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time


class MeasurementError(Exception):
    """Непридатний host-лічильник або виконання, не закон SENS."""


def integer(path: Path) -> int:
    try:
        value = path.read_text(encoding="ascii").strip()
        if not value.isascii() or not value.isdecimal():
            raise ValueError("не десятковий лічильник")
        return int(value)
    except (OSError, ValueError) as exc:
        raise MeasurementError(f"неможливо прочитати {path}: {exc}") from exc


class PackageCounter:
    """Root borrowed path. Host sysfs files read-only; власних FD не зберігаємо.

    1) Чому max_energy_range_uj береться з того самого package?
    2) Чому core/uncore піддомени не можна сумувати з package?
    3) Чому перевіряємо діапазон перед та після виконання?
    4) Чому два wrap за один запуск НЕ можна визначити з двох значень?
    """
    def __init__(self, root: Path, package: int, simulated: bool):
        self.simulated = simulated
        self.path = root / f"intel-rapl:{package}"
        try:
            name = (self.path / "name").read_text(encoding="ascii").strip()
        except OSError as exc:
            raise MeasurementError("немає читабельного RAPL package: " + str(exc)) from exc
        if name != f"package-{package}":
            raise MeasurementError(f"потрібен package-{package}, отримано {name!r}")
        self.energy = self.path / "energy_uj"
        self.maximum = integer(self.path / "max_energy_range_uj")
        if self.maximum <= 1:
            raise MeasurementError("неправильний max_energy_range_uj")
        self.read()

    def read(self) -> int:
        value = integer(self.energy)
        if value < 0 or value >= self.maximum:
            raise MeasurementError("energy_uj поза фізичною межею")
        return value

    def delta(self, before: int, after: int, elapsed_ns: int) -> int:
        if elapsed_ns <= 0:
            raise MeasurementError("недійсний монотонний час")
        # Захист від можливого MULTI-wrap: 500W — консервативний host
        # верхній поріг для цієї лабораторної методики, НЕ закон SENS.
        # Для synthetic fixture перевіряємо лише арифметику одного wrap.
        if not self.simulated and elapsed_ns * 500 >= self.maximum * 1000:
            raise MeasurementError("лічильник міг обернутися двічі; скоротіть запуск")
        return (after - before) % self.maximum


def execute(path: Path, expected: int) -> int:
    """Повертає власний monotonic elapsed_ns, а не енергію."""
    t0 = time.perf_counter_ns()
    try:
        proc = subprocess.run([str(path)], capture_output=True, timeout=40, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise MeasurementError(f"не вдалося виконати {path.name}: {exc}") from exc
    elapsed = time.perf_counter_ns() - t0
    if proc.returncode != expected or proc.stdout or proc.stderr:
        raise MeasurementError(
            f"{path.name}: exit={proc.returncode}, очікувано={expected}, "
            f"stdout={len(proc.stdout)} stderr={len(proc.stderr)}"
        )
    return elapsed


def program_pairs(items: list[str]) -> list[tuple[str, Path]]:
    result = []
    seen = set()
    for item in items:
        if "=" not in item:
            raise MeasurementError("потрібен --program НАЗВА=ПОВНИЙ_ШЛЯХ")
        label, path = item.split("=", 1)
        if not label or not label.isascii() or not label.replace("-", "").isalnum():
            raise MeasurementError("неправильна назва програми")
        if label in seen:
            raise MeasurementError("повторна назва програми")
        seen.add(label)
        p = Path(path).resolve()
        if not p.is_file() or not os.access(p, os.X_OK):
            raise MeasurementError(f"відсутній виконуваний файл: {path}")
        result.append((label, p))
    if not result:
        raise MeasurementError("немає жодної програми для порівняння")
    return result


def measure(args: argparse.Namespace) -> str:
    """Збирає результат у пам'яті; stdout ТІЛЬКИ після усіх перевірок.

    1) Чому перед виміром незалежно перевіряємо ВСІ чотири двійкові файли?
    2) Чому випадковий порядок не потрібний, а порядок обертається за раундами?
    3) Чому значення package не можна приписувати одному процесу?
    4) Чому mock-root не дозволяє оголошувати фізичні джоулі?
    """
    pairs = program_pairs(args.program)
    if not 0 <= args.expected <= 255:
        raise MeasurementError("код оракула має бути 0..255")
    if not 1 <= args.repeats <= 50 or not 0 <= args.warmup <= 10:
        raise MeasurementError("неправильна кількість повторів")
    for _, path in pairs:
        execute(path, args.expected)
    if args.verify_only:
        return "FIB-CROSS-VERIFY-PASS програми=" + str(len(pairs)) + " енергія=НЕ-ВИМІРЯНО"

    simulated = args.mock_root is not None
    root = Path(args.mock_root) if simulated else Path("/sys/class/powercap")
    counter = PackageCounter(root, args.package, simulated)
    for _, path in pairs:
        for _ in range(args.warmup):
            execute(path, args.expected)

    energies = {label: [] for label, _ in pairs}
    times = {label: [] for label, _ in pairs}
    for i in range(args.repeats):
        ordered = pairs[i % len(pairs):] + pairs[:i % len(pairs)]
        for label, path in ordered:
            before = counter.read()
            t0 = time.perf_counter_ns()
            execute(path, args.expected)
            elapsed = time.perf_counter_ns() - t0
            after = counter.read()
            energies[label].append(counter.delta(before, after, elapsed))
            times[label].append(elapsed // 1000)

    mode = "СИМУЛЬОВАНО-НЕ-ФІЗИЧНА-ЕНЕРГІЯ" if simulated else "АПАРАТНИЙ-RAPL"
    lines = [f"FIB-CROSS-ENERGY режим={mode} package={args.package} "
             f"range_uj={counter.maximum} repeats={args.repeats}"]
    for label, _ in pairs:
        lines.append(
            f"FIB-CROSS {label} "
            f"медіана_мкДж={int(statistics.median(energies[label]))} "
            f"медіана_мкс={int(statistics.median(times[label]))} "
            f"мін_мкДж={min(energies[label])} макс_мкДж={max(energies[label])}"
        )
    lines.append("FIB-CROSS-ENERGY-PASS " + mode)
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--program", action="append", required=True)
    parser.add_argument("--expected", type=int, required=True)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--package", type=int, default=0)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--mock-root", help="ЛИШЕ тест; вихід завжди SIMULATED")
    args = parser.parse_args()
    try:
        if args.package < 0 or args.package > 255:
            raise MeasurementError("неправильний номер CPU package")
        output = measure(args)
    except MeasurementError as exc:
        print(f"FIB-CROSS-ВІДМОВА: {exc}", file=sys.stderr)
        return 2
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
