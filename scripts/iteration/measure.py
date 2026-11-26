#!/usr/bin/env python3
"""Відтворюваний W1/W2 вимір циклу headless-зміни для FPC 3.2.2/3.2.4.

Вимірюється повний M0.2 build.sh (FPC -B, тест фрейму й nativeeval),
після окремого повного scripts/test.sh preflight. Команди не задаються
рядком користувача: runner запускає лише закріплені сценарії репозиторію.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
FPC_324_SOURCE = "66940ee65006538dba16b4c584d3cfb1cc08985e"
ALLOWED_VERSIONS = {"3.2.2", "3.2.4"}
MIN_REPETITIONS = 20
MAX_REPETITIONS = 100
PRECHECK_COMMAND = ["bash", "scripts/test.sh"]
MEASURE_COMMAND = ["bash", "scripts/build.sh"]


class MeasurementError(RuntimeError):
    """Помилка підготовки або виконання вимірювального циклу."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def percentile(values: list[int], percent: float) -> float:
    """Лінійний квантиль типу 7; одиниця входу й виходу — наносекунди."""
    if not values or any(not isinstance(value, int) or value <= 0 for value in values):
        raise ValueError("потрібні лише додатні цілочисельні виміри")
    if not 0 <= percent <= 100:
        raise ValueError("percent має бути в межах 0..100")
    ordered = sorted(values)
    position = (len(ordered) - 1) * percent / 100
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def summary(values: list[int]) -> dict[str, int | float]:
    if len(values) < MIN_REPETITIONS:
        raise ValueError(f"потрібно щонайменше {MIN_REPETITIONS} вимірів")
    return {
        "count": len(values),
        "p10_ns": round(percentile(values, 10), 2),
        "p50_ns": round(statistics.median(values), 2),
        "p90_ns": round(percentile(values, 90), 2),
    }


def validate_repetitions(value: int) -> int:
    if not MIN_REPETITIONS <= value <= MAX_REPETITIONS:
        raise ValueError(f"повтори мають бути в межах {MIN_REPETITIONS}..{MAX_REPETITIONS}")
    return value


def resolve_executable(value: str | None, env_name: str) -> Path:
    candidate = value or os.environ.get(env_name) or shutil.which("fpc")
    if not candidate:
        raise MeasurementError("не знайдено FPC; задайте --fpc або PATH")
    resolved = shutil.which(candidate) if os.sep not in candidate else candidate
    if not resolved:
        raise MeasurementError(f"не знайдено виконуваний файл: {candidate}")
    path = Path(resolved).expanduser().resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise MeasurementError(f"FPC не є виконуваним файлом: {path}")
    return path


def command_text(argv: list[str], *, cwd: Path = ROOT,
                 env: dict[str, str] | None = None, timeout: int = 15) -> str:
    try:
        result = subprocess.run(
            argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=timeout, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise MeasurementError(f"команда не завершилася: {argv!r}: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace")[-2000:]
        raise MeasurementError(f"команда {argv!r} завершилася з кодом {result.returncode}: {detail}")
    try:
        return result.stdout.decode("utf-8", errors="strict").strip()
    except UnicodeDecodeError as exc:
        raise MeasurementError(f"команда {argv!r} повернула не UTF-8") from exc


def inspect_compiler(fpc: Path, expected_version: str, rtl_id: str,
                     source_revision: str | None) -> tuple[dict[str, Any], dict[str, str]]:
    if expected_version not in ALLOWED_VERSIONS:
        raise MeasurementError("дозволені лише host-baseline FPC 3.2.2 та кандидат 3.2.4")
    if not rtl_id.strip():
        raise MeasurementError("--rtl-id обов'язковий: RTL не можна виводити з назви компілятора")
    if expected_version == "3.2.4":
        if source_revision != FPC_324_SOURCE:
            raise MeasurementError(
                "FPC 3.2.4 допускається лише з pinned source revision " + FPC_324_SOURCE
            )
    elif source_revision and not re.fullmatch(r"[0-9a-f]{40,64}", source_revision):
        raise MeasurementError("--source-revision має бути повним SHA-1/SHA-256")

    environment = os.environ.copy()
    environment["PATH"] = str(fpc.parent) + os.pathsep + environment.get("PATH", "")
    environment["FPC"] = str(fpc)
    version = command_text([str(fpc), "-iV"], env=environment)
    target_cpu = command_text([str(fpc), "-iTP"], env=environment)
    target_os = command_text([str(fpc), "-iTO"], env=environment)
    if version != expected_version:
        raise MeasurementError(f"очікувався FPC {expected_version}, отримано {version}")
    if target_cpu.casefold() not in {"x86_64", "x86-64"}:
        raise MeasurementError(f"очікувався host target x86_64, отримано {target_cpu}")
    if target_os.casefold() != "linux":
        raise MeasurementError(
            f"очікувався host target Linux, отримано {target_os}; embedded 3.3.1 — окремий P0"
        )
    return {
        "path": str(fpc),
        "binary_sha256": sha256_file(fpc),
        "version": version,
        "target_cpu": target_cpu,
        "target_os": target_os,
        "rtl_id": rtl_id,
        "source_revision": source_revision or "не зафіксовано для готового пакета 3.2.2",
        "source_revision_provenance": (
            "operator-declared; executable SHA256 is recorded separately; "
            "this runner does not independently attest the compiler build"
            if source_revision else "not supplied for the installed 3.2.2 control binary"
        ),
        "distribution_id": "FPC " + expected_version,
    }, environment


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return None


def host_info() -> dict[str, Any]:
    cpu_model = None
    cpuinfo = read_text(Path("/proc/cpuinfo"))
    if cpuinfo:
        for line in cpuinfo.splitlines():
            if line.lower().startswith(("model name", "hardware")) and ":" in line:
                cpu_model = line.split(":", 1)[1].strip()
                break
    governors = sorted({value for path in Path("/sys/devices/system/cpu").glob(
        "cpufreq/policy*/scaling_governor") if (value := read_text(path))})
    if not governors:
        governor = read_text(Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"))
        if governor:
            governors = [governor]
    intel_no_turbo = read_text(Path("/sys/devices/system/cpu/intel_pstate/no_turbo"))
    generic_boost = read_text(Path("/sys/devices/system/cpu/cpufreq/boost"))
    try:
        affinity = sorted(os.sched_getaffinity(0))
    except (AttributeError, OSError):
        affinity = None
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor() or cpu_model,
        "cpu_model": cpu_model,
        "python": platform.python_version(),
        "cpu_affinity": affinity,
        "governors_seen": governors,
        "intel_pstate_no_turbo": intel_no_turbo,
        "generic_boost": generic_boost,
        "power_settings_changed": False,
    }


def repository_info() -> dict[str, Any]:
    commit = command_text(["git", "rev-parse", "HEAD"])
    branch = command_text(["git", "branch", "--show-current"])
    dirty = command_text(["git", "status", "--porcelain", "--untracked-files=no"])
    if dirty:
        raise MeasurementError(
            "робоче дерево має tracked-зміни; зафіксуйте код перед вимірюванням"
        )
    return {"commit": commit, "branch": branch, "tracked_tree_dirty": False}


def validate_host() -> None:
    if platform.system() != "Linux" or platform.machine().casefold() not in {"x86_64", "amd64"}:
        raise MeasurementError("цей W1/W2 runner вимірює лише host Linux x86_64")


def load_energy_module():
    path = ROOT / "scripts" / "energy" / "measure.py"
    spec = importlib.util.spec_from_file_location("wsm_energy_measure", path)
    if spec is None or spec.loader is None:
        raise MeasurementError("не вдалося завантажити чинний RAPL-колектор")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class PackageRapl:
    """Пакетний лічильник ОС; джоулі не приписуються одному процесу."""
    def __init__(self) -> None:
        self.module = None
        self.zones = []
        self.error = "немає доступного package RAPL"
        try:
            self.module = load_energy_module()
            all_zones = self.module.discover_zones("/sys/class/powercap")
            self.zones = [zone for zone in all_zones if zone.name.startswith("package-")]
            if not self.zones:
                raise ValueError("відсутня package-зона RAPL")
            initial = self.snapshot()  # перевірити права до першого таймованого запуску
            if initial is None:
                raise PermissionError(self.error or "package RAPL не читається")
            self.error = ""
        except Exception as exc:  # sensor unavailable must not fabricate zero
            self.module = None
            self.zones = []
            self.error = f"{type(exc).__name__}: {exc}"

    def snapshot(self) -> dict[str, int] | None:
        if not self.zones:
            return None
        try:
            return {zone.name: zone.read() for zone in self.zones}
        except Exception as exc:
            self.error = f"{type(exc).__name__}: {exc}"
            return None

    def delta(self, before: dict[str, int] | None,
              after: dict[str, int] | None, elapsed_ns: int) -> dict[str, int] | None:
        if not before or not after or self.module is None:
            return None
        if elapsed_ns <= 0:
            self.error = "непозитивний інтервал RAPL"
            return None
        result: dict[str, int] = {}
        try:
            for zone in self.zones:
                if elapsed_ns >= zone.maximum:
                    raise ValueError("інтервал допускає невідомі оберти RAPL")
                result[zone.name] = self.module.counter_delta(
                    before[zone.name], after[zone.name], zone.maximum
                )
            self.error = ""
            return result
        except Exception as exc:
            self.error = f"{type(exc).__name__}: {exc}"
            return None


def write_log(directory: Path, name: str, payload: bytes) -> dict[str, Any]:
    path = directory / name
    with path.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    return {"file": name, "bytes": len(payload), "sha256": sha256_bytes(payload)}


def run_command(argv: list[str], environment: dict[str, str], timeout_seconds: int,
                directory: Path, label: str, rapl: PackageRapl
                ) -> tuple[int, int, dict[str, Any]]:
    start_utc = utc_now()
    energy_before = rapl.snapshot()
    start_ns = time.perf_counter_ns()
    try:
        result = subprocess.run(
            argv, cwd=ROOT, env=environment, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=timeout_seconds, check=False,
        )
        timed_out = False
        return_code = result.returncode
        stdout, stderr = result.stdout, result.stderr
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        return_code = None
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
    except OSError as exc:
        raise MeasurementError(f"не вдалося запустити {argv!r}: {exc}") from exc
    elapsed_ns = time.perf_counter_ns() - start_ns
    energy_after = rapl.snapshot()
    energy = rapl.delta(energy_before, energy_after, elapsed_ns)
    stdout_info = write_log(directory, label + ".stdout.log", stdout)
    stderr_info = write_log(directory, label + ".stderr.log", stderr)
    sample = {
        "label": label,
        "started_utc": start_utc,
        "finished_utc": utc_now(),
        "elapsed_ns": elapsed_ns,
        "exit_code": return_code,
        "timed_out": timed_out,
        "rapl_before_uj": energy_before,
        "rapl_after_uj": energy_after,
        "energy_package_uj": energy,
        "energy_not_measured_reason": None if energy is not None else rapl.error,
        "energy_boundary": "package-wide; includes background work; not per-process",
        "stdout": stdout_info,
        "stderr": stderr_info,
    }
    if timed_out or return_code != 0:
        raise MeasurementError(
            f"{label}: команда {argv!r} завершилася невдало; "
            f"timeout={timed_out}, exit={return_code}; журнали у {directory}"
        )
    return start_ns, elapsed_ns, sample


def run_series(name: str, repetitions: int, warmup: int, environment: dict[str, str],
               timeout_seconds: int, output_dir: Path, rapl: PackageRapl) -> dict[str, Any]:
    discarded = []
    for index in range(warmup):
        _, _, sample = run_command(
            MEASURE_COMMAND, environment, timeout_seconds, output_dir,
            f"{name}.warmup.{index + 1:02d}", rapl
        )
        sample["elapsed_in_statistics"] = False
        discarded.append(sample)
    samples = []
    for index in range(repetitions):
        _, _, sample = run_command(
            MEASURE_COMMAND, environment, timeout_seconds, output_dir,
            f"{name}.sample.{index + 1:02d}", rapl
        )
        sample["elapsed_in_statistics"] = True
        samples.append(sample)
    durations = [sample["elapsed_ns"] for sample in samples]
    energy_values = [sample["energy_package_uj"] for sample in samples
                     if sample["energy_package_uj"] is not None]
    energy_status = (
        "PACKAGE_BOUNDARY_PARTIALLY_MEASURED" if 0 < len(energy_values) < len(samples)
        else "PACKAGE_BOUNDARY_MEASURED" if len(energy_values) == len(samples)
        else "ENERGY_NOT_MEASURED"
    )
    energy_reasons = sorted({
        sample["energy_not_measured_reason"]
        for sample in samples
        if sample["energy_not_measured_reason"]
    })
    return {
        "warmup_runs": warmup,
        "warmup_samples": discarded,
        "samples": samples,
        "statistics": summary(durations),
        "energy_status": energy_status,
        "energy_measured_samples": len(energy_values),
        "energy_not_measured_reasons": energy_reasons,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="W1/W2: 20+ повторів headless build без/з додатковим прогрівом"
    )
    parser.add_argument("--fpc", help="точний шлях до FPC executable")
    parser.add_argument("--expected-version", required=True, choices=sorted(ALLOWED_VERSIONS))
    parser.add_argument("--rtl-id", required=True, help="точна ідентичність RTL-пакета/збірки")
    parser.add_argument("--toolchain-id", required=True, help="людиночитаний ID набору compiler+RTL")
    parser.add_argument("--source-revision", help="повний SHA джерел FPC (обов'язково для 3.2.4)")
    parser.add_argument("--repetitions", type=int, default=20,
                        help="кількість вимірювань у кожній серії (20..100)")
    parser.add_argument("--timeout-seconds", type=int, default=240)
    parser.add_argument("--preflight-timeout-seconds", type=int, default=1800)
    parser.add_argument("--output-dir", required=True,
                        help="нова директорія для звіту та сирих журналів; не перезаписується")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    output_dir: Path | None = None
    output_created = False
    try:
        repetitions = validate_repetitions(args.repetitions)
        if args.timeout_seconds < 1 or args.preflight_timeout_seconds < 1:
            raise MeasurementError("тайм-аути мають бути додатними")
        fpc = resolve_executable(args.fpc, "FPC")
        toolchain, environment = inspect_compiler(
            fpc, args.expected_version, args.rtl_id, args.source_revision
        )
        validate_host()
        if not args.toolchain_id.strip():
            raise MeasurementError("--toolchain-id не може бути порожнім")
        repository = repository_info()
        output_dir = Path(args.output_dir).expanduser().resolve()
        output_dir.parent.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(exist_ok=False)
        output_created = True
        rapl = PackageRapl()
        _, preflight_ns, preflight = run_command(
            PRECHECK_COMMAND, environment, args.preflight_timeout_seconds,
            output_dir, "preflight.full-headless-gate", rapl
        )
        preflight["elapsed_ns"] = preflight_ns
        no_extra_warmup = run_series("no-extra-warmup", repetitions, 0, environment,
                                     args.timeout_seconds, output_dir, rapl)
        extra_warmup = run_series("one-extra-warmup", repetitions, 1, environment,
                                  args.timeout_seconds, output_dir, rapl)
        energy_states = {no_extra_warmup["energy_status"], extra_warmup["energy_status"]}
        if energy_states == {"PACKAGE_BOUNDARY_MEASURED"}:
            overall_energy = "PACKAGE_BOUNDARY_MEASURED"
        elif energy_states == {"ENERGY_NOT_MEASURED"}:
            overall_energy = "ENERGY_NOT_MEASURED"
        else:
            overall_energy = "PACKAGE_BOUNDARY_PARTIALLY_MEASURED"
        report = {
            "schema": "wsm-lazarus-iteration-measurement/1",
            "created_utc": utc_now(),
            "purpose": "W1 wall-clock iteration / W2 optional package-boundary energy",
            "scope": {
                "preflight": "full scripts/test.sh; outside measured iteration time",
                "measured_command": MEASURE_COMMAND,
                "measured_work": "scripts/build.sh: -B full headless build + envframe + nativeeval checks",
                "not_claimed": [
                    "human thinking time", "process-attributed energy", "SENS semantic parity beyond existing gates",
                    "OS page-cache coldness", "embedded 3.3.1 performance",
                ],
            },
            "repository": repository,
            "host": host_info(),
            "toolchain": {**toolchain, "requested_toolchain_id": args.toolchain_id},
            "build_inputs": {
                "build_script_sha256": sha256_file(ROOT / "scripts" / "build.sh"),
                "preflight_script_sha256": sha256_file(ROOT / "scripts" / "test.sh"),
                "nativeeval_script_sha256": sha256_file(ROOT / "scripts" / "test-nativeeval.sh"),
                "fpc_flags": {
                    "headless_binary": ["-B", "-Mobjfpc", "-O1"],
                    "envframe_smoke": ["-B", "-Mobjfpc"],
                    "nativeeval_checks": ["-B", "-Mobjfpc", "-Cr", "-Co", "-Ci", "-gl", "-gh"],
                },
            },
            "preflight": preflight,
            "series": {"after_preflight_no_extra_warmup": no_extra_warmup,
                       "after_one_extra_discarded_build": extra_warmup},
            "true_cold_cache_series": {
                "status": "UNAVAILABLE",
                "reason": "full scripts/test.sh preflight reads/builds sources; page cache is not flushed or OS rebooted",
            },
            "energy_status": overall_energy,
            "energy_scope_note": (
                "RAPL package energy includes all activity on the package and cannot be attributed "
                "to the FPC process; never subtract the idle value and call it process energy."
            ),
            "method": {
                "first_definition": "measured build cycles after full preflight, without an extra discarded benchmark build; build.sh removes build/m0.2",
                "warm_definition": "one successful additional unmeasured build.sh immediately before the second measured series",
                "cache_limit": "true cold page-cache measurements are unavailable: preflight warms source files, and the runner does not flush OS caches or reboot",
                "quantiles": "type-7 linear interpolation; p10/p50/p90 over elapsed monotonic nanoseconds",
                "minimum_repetitions_per_series": MIN_REPETITIONS,
            },
        }
        report_path = output_dir / "report.json"
        with report_path.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        print(
            "ITERATION-MEASURE-PASS "
            f"fpc={toolchain['version']} no-extra-warmup={repetitions} extra-warmup={repetitions} "
            f"true-cold=UNAVAILABLE energy={overall_energy} report={report_path}"
        )
        return 0
    except (MeasurementError, ValueError, OSError, subprocess.SubprocessError) as exc:
        if output_created and output_dir is not None and output_dir.is_dir():
            failure = output_dir / "FAILED.txt"
            try:
                failure.write_text(f"{utc_now()}\n{type(exc).__name__}: {exc}\n", encoding="utf-8")
            except OSError:
                pass
        print(f"ITERATION-MEASURE-FAIL: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
