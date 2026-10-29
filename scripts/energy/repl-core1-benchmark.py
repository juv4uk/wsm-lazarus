#!/usr/bin/env python3
"""Парне вимірювання усталених інтерактивних REPL Core1 і pinned SENS.

Енергія доступна лише для package-зони RAPL; вона включає весь комп'ютер.
Цей дослід не є оцінкою енергії окремого процесу або рейтингом мов.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pwd
import random
import re
import resource
import statistics
import subprocess
import sys
import time
import math
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import measure

FORM = "(додати 5000 5000)"
RESULT = "10000"
CORE1_BANNER_PREFIXES = ("SENS Core1 REPL", "Допущених визначень:",
                         "Двійковий літерал —", "Команди:")
SENS_BANNER_PREFIXES = ("SENS REPL версії ", "Поверхня:", "Символи можна вводити",
                        "D1 у канонічному поданні —", "Ctrl-C або Ctrl-D — вихід.")


def validate_output(output: bytes, lane: str, count: int) -> list[str]:
    try:
        text = output.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ValueError("stdout не є UTF-8") from error
    lines = text.splitlines()
    if lane == "core1":
        banners = CORE1_BANNER_PREFIXES
    elif lane == "sens":
        banners = SENS_BANNER_PREFIXES
    else:
        raise ValueError("невідома лінія REPL")
    replies, saw_banner = [], False
    for line in lines:
        if not line:
            continue
        if lane == "sens" and line.startswith("sens[укр]> "):
            line = line[len("sens[укр]> "):]
            if not line:
                continue
        if line == RESULT:
            replies.append(line)
        elif any(line.startswith(prefix) for prefix in banners):
            if replies:
                raise ValueError("банер після першої відповіді")
            saw_banner = True
        else:
            raise ValueError("неочікуваний stdout REPL: " + repr(line[:160]))
    if lane == "core1" and not saw_banner:
        raise ValueError("немає банера Core1 REPL")
    if len(replies) != count:
        raise ValueError(f"очікували {count} відповідей {RESULT}, отримали {len(replies)}")
    return replies


def validate_stderr(output: bytes, lane: str, count: int) -> None:
    if lane == "sens":
        if output:
            raise ValueError("SENS REPL вивів stderr: " + repr(output[:200]))
        return
    text = output.decode("utf-8", errors="strict")
    expected = "????> " * (count + 1) + "; сеанс завершено\n"
    if text != expected:
        raise ValueError("неочікуваний stderr Core1 REPL: " + repr(text[:200]))


def run_repl(lane: str, command: list[str], count: int, core: int,
             timeout: float) -> tuple[bytes, float]:
    payload = ((FORM + "\n") * count).encode("utf-8")
    if lane == "core1":
        payload += b":quit\n"
    started = time.monotonic_ns()
    options = {"stdin": subprocess.PIPE, "stdout": subprocess.PIPE,
               "stderr": subprocess.PIPE, "start_new_session": True}
    if os.geteuid() == 0:
        account = pwd.getpwnam(os.environ["SUDO_USER"])
        options.update(user=account.pw_uid, group=account.pw_gid, extra_groups=[])
    process = subprocess.Popen(command, **options)
    try:
        os.sched_setaffinity(process.pid, {core})
        stdout, stderr = process.communicate(payload, timeout=timeout)
    except BaseException:
        process.kill()
        process.communicate()
        raise
    elapsed = (time.monotonic_ns() - started) / 1e9
    if process.returncode != 0:
        raise ValueError(f"{lane} завершився з кодом {process.returncode}: {stderr[:1000]!r}")
    validate_stderr(stderr, lane, count)
    validate_output(stdout, lane, count)
    return stdout, elapsed


def identity(path: Path) -> dict:
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    low = math.floor(index)
    high = math.ceil(index)
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def paired_analysis(rows: list[dict], seed: int) -> dict:
    by_block = {}
    for row in rows:
        by_block.setdefault(row["block"], {})[row["lane"]] = row
    package = {name: [] for name in ("core1", "sens")}
    idle_adjusted = {name: [] for name in ("core1", "sens")}
    for block in sorted(by_block):
        group = by_block[block]
        idle = group["idle"]
        idle_watts = idle["energy_uj"]["package-0"] / 1e6 / idle["seconds"]
        for name in package:
            active = group[name]
            package[name].append(active["energy_uj"]["package-0"] / 1e6)
            idle_adjusted[name].append(
                package[name][-1] - idle_watts * active["seconds"])
    rng = random.Random(seed)

    def bootstrap_median_ci(values: list[float]) -> dict:
        medians = []
        for _ in range(10000):
            sample = [values[rng.randrange(len(values))] for _ in values]
            medians.append(statistics.median(sample))
        return {"median": statistics.median(values), "bootstrap_95_percentile_interval":
                [percentile(medians, .025), percentile(medians, .975)]}

    return {
        "paired_package_energy_difference_core1_minus_sens_joules":
            bootstrap_median_ci([a - b for a, b in zip(package["core1"], package["sens"])]),
        "paired_idle_rate_adjusted_difference_core1_minus_sens_joules":
            bootstrap_median_ci([a - b for a, b in zip(idle_adjusted["core1"], idle_adjusted["sens"])]),
        "idle_rate_adjusted_core1_joules_per_10000_forms": bootstrap_median_ci(idle_adjusted["core1"]),
        "idle_rate_adjusted_sens_joules_per_10000_forms": bootstrap_median_ci(idle_adjusted["sens"]),
        "interpretation": "Exploratory package-level difference; idle-rate adjustment is a rough control, not per-process energy. Background activity remains confounded.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--sens", type=Path, required=True)
    parser.add_argument("--core1", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--forms", type=int, default=10000)
    parser.add_argument("--rounds", type=int, default=30)
    parser.add_argument("--core", type=int, default=2)
    parser.add_argument("--seed", type=int, default=346)
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()
    if args.rounds < 30 or args.forms < 1 or args.output.exists():
        parser.error("потрібні ≥30 блоків, додатна кількість форм і новий файл звіту")
    root, sens, core1 = (p.resolve() for p in (args.root, args.sens, args.core1))
    authority = root / "external/sens"
    repo = Path(__file__).resolve().parents[2]
    pinned_sha = subprocess.check_output(["git", "-C", str(authority), "rev-parse", "HEAD"], text=True).strip()
    contract = authority / "contracts/language-contract-12.lisp"
    if not contract.is_file() or '(version . "12.0")' not in contract.read_text(encoding="utf-8"):
        raise ValueError("відсутній pinned Contract 12.0")

    zones = measure.discover_zones("/sys/devices/virtual/powercap/intel-rapl")
    # Semantic and D24 physical preflight: both engines must agree before RAPL sampling.
    tmp = Path("/dev/shm")
    source = tmp / f"sens-repl-d24-{os.getpid()}.lisp"
    physical = tmp / f"sens-repl-d24-{os.getpid()}.sens"
    source.write_text(FORM + "\n", encoding="utf-8")
    witness_provenance = None
    try:
        mint = root / "build/energy/bin/senst5m"
        subprocess.run([str(sens), "--t5m-mint", str(source), str(physical)], cwd=root,
                       check=True, capture_output=True, timeout=30)
        view = subprocess.run([str(mint), "--перегляд", str(physical)], cwd=root,
                              check=True, capture_output=True, text=True, timeout=30).stdout
        numeric_words = re.findall(r"\b[01]{24}\b", view)
        expected_d24_5000 = "000000000001001110001000"
        if numeric_words != [expected_d24_5000, expected_d24_5000]:
            raise ValueError("фізичний T5M witness не містить два точні D24(5000)")
        witness_provenance = {
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "physical_t5m_sha256": hashlib.sha256(physical.read_bytes()).hexdigest(),
            "physical_t5m_bytes": physical.stat().st_size,
        }
        oracle_out, _ = run_repl("sens", [str(sens)], 1, args.core, args.timeout)
        core_out, _ = run_repl("core1", [str(core1), str(root)], 1, args.core, args.timeout)
        validate_output(oracle_out, "sens", 1)
        validate_output(core_out, "core1", 1)
    finally:
        source.unlink(missing_ok=True)
        physical.unlink(missing_ok=True)

    commands = {"core1": [str(core1), str(root)], "sens": [str(sens)]}
    # Each timed process has a fresh process, but handles multiple forms in one persistent session.
    # Compilation, oracle checks, and output validation are outside the RAPL interval.
    results, rows = [], []
    rng = random.Random(args.seed)
    for lane in commands:
        _, pilot = run_repl(lane, commands[lane], args.forms, args.core, args.timeout)
        results.append({"lane": lane, "pilot_seconds": pilot,
                        "forms_per_session": args.forms})
    idle_seconds = max(0.25, min(10.0, statistics.median(r["pilot_seconds"] for r in results)))
    owner = None
    if os.geteuid() == 0:
        user_name = os.environ.get("SUDO_USER")
        if not user_name:
            raise ValueError("запускайте через sudo від звичайного користувача")
        account = pwd.getpwnam(user_name)
        owner = (account.pw_uid, account.pw_gid)
    for block in range(args.rounds):
        order = ["core1", "sens", "idle"]
        rng.shuffle(order)
        for lane in order:
            before_load = Path("/proc/loadavg").read_text().strip()
            busy_before = measure.cpu_busy_ticks()
            proc = None
            child_cpu = None
            with measure.Sampler(zones) as sampler:
                if lane == "idle":
                    time.sleep(idle_seconds)
                    elapsed = idle_seconds
                    stdout = b""
                else:
                    command = commands[lane]
                    # Start before opening the meter, then send all forms within the interval.
                    options = {"stdin": subprocess.PIPE, "stdout": subprocess.PIPE,
                               "stderr": subprocess.PIPE, "start_new_session": True}
                    if owner is not None:
                        options.update(user=owner[0], group=owner[1], extra_groups=[])
                    child_before = resource.getrusage(resource.RUSAGE_CHILDREN)
                    start = time.monotonic_ns()
                    proc = subprocess.Popen(command, **options)
                    os.sched_setaffinity(proc.pid, {args.core})
                    payload = ((FORM + "\n") * args.forms).encode("utf-8")
                    if lane == "core1":
                        payload += b":quit\n"
                    stdout, stderr = proc.communicate(payload, timeout=args.timeout)
                    elapsed = (time.monotonic_ns() - start) / 1e9
                    child_after = resource.getrusage(resource.RUSAGE_CHILDREN)
                    child_cpu = ((child_after.ru_utime - child_before.ru_utime) +
                                 (child_after.ru_stime - child_before.ru_stime))
                    if proc.returncode != 0:
                        raise ValueError(f"помилка {lane}: exit={proc.returncode}, stderr={stderr[:300]!r}")
            sample = sampler.result()
            if lane != "idle":
                validate_output(stdout, lane, args.forms)
                validate_stderr(stderr, lane, args.forms)
            rows.append({**sample, "block": block, "lane": lane,
                         "forms": args.forms if lane != "idle" else 0,
                         "elapsed_process_seconds": elapsed,
                         "child_cpu_seconds": child_cpu,
                         "host_busy_ticks": measure.cpu_busy_ticks() - busy_before,
                         "load_before": before_load,
                         "temperature_before": measure.temperatures()})
        print(f"Завершено блок {block + 1}/{args.rounds}", flush=True)

    summaries = {}
    for lane in ("core1", "sens", "idle"):
        subset = [r for r in rows if r["lane"] == lane]
        per_zone = {}
        for zone in zones:
            energy = [row["energy_uj"][zone.name] / 1e6 for row in subset]
            per_zone[zone.name] = {"median_package_or_zone_joules": statistics.median(energy),
                                   "p10_joules": sorted(energy)[int(len(energy) * .1)],
                                   "p90_joules": sorted(energy)[min(len(energy)-1, int(len(energy)*.9))]}
        summaries[lane] = {"median_elapsed_seconds": statistics.median(r["elapsed_process_seconds"] for r in subset),
                           "median_child_cpu_seconds": statistics.median(r["child_cpu_seconds"] for r in subset) if lane != "idle" else None,
                           "median_forms_per_second": (args.forms / statistics.median(r["elapsed_process_seconds"] for r in subset)) if lane != "idle" else None,
                           "zones": per_zone}
    report = {
        "schema": "sens-repl-energy-exploratory/1",
        "scope": "EXPLORATORY_WHOLE_PACKAGE_RAPL_SHARED_DESKTOP",
        "interpretation": "RAPL covers package/zone and all processes; not per-process energy; do not claim a winner unless paired signal is separable.",
        "workload": {"source_projection": "укр", "form": FORM, "expected_projection": RESULT,
                     "physical_witness": "D24 minted with pinned T5M reader", "forms_per_session": args.forms,
                     "persistent_session": True},
        "physical_witness": witness_provenance,
        "provenance": {"wsm_main_sha": subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(),
                       "wsm_worktree": subprocess.check_output(["git", "-C", str(repo), "status", "--short"], text=True).strip(),
                       "sens_authority_sha": pinned_sha, "core1_executable": identity(core1),
                       "sens_executable": identity(sens), "machine": os.uname().machine,
                       "benchmark_script": identity(Path(__file__)),
                       "fpc_version": subprocess.check_output(["fpc", "-iV"], text=True).strip(),
                       "core1_build_flags": "-B -Mobjfpc -Cr -Co -Ci -gl",
                       "sens_cli_version": subprocess.check_output([str(sens), "--version"], text=True).strip(),
                       "kernel": os.uname().release, "cpuinfo": Path("/proc/cpuinfo").read_text(),
                       "governor": Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").read_text().strip(),
                       "load_after": Path("/proc/loadavg").read_text().strip(),
                       "zone_scope": [{"name": z.name, "path": str(z.path), "max_energy_uj": z.maximum} for z in zones]},
        "protocol": {"rounds": args.rounds, "seed": args.seed, "cpu_affinity": [args.core],
                     "randomized_order": True, "idle_duration_seconds": idle_seconds,
                     "sample_period_seconds": 0.05},
        "pilot": results, "summary": summaries,
        "paired_analysis": paired_analysis(rows, args.seed), "samples": rows,
    }
    measure.publish_report(args.output, report, owner)
    print(json.dumps(summaries, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
