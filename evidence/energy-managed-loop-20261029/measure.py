#!/usr/bin/env python3
"""Холодні й сталосесійні Go, HotSpot та .NET профілі з сирим Intel RAPL."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import pwd
import random
import re
import resource
import select
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BIN = ROOT / "build/energy/managed-d12-loop"
N = 8_388_361
EXPECTED = 173
LANES = ("go", "hotspot", "dotnet")
JAVA_FLAGS = ("-Xms32m", "-Xmx32m", "-XX:+UseSerialGC", "-XX:+TieredCompilation",
              "-XX:ActiveProcessorCount=1")

sys.path.insert(0, str(ROOT / "scripts/energy"))
import measure as rapl  # noqa: E402


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    low, high = math.floor(index), math.ceil(index)
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def bootstrap_median(values: list[float], seed: int) -> dict:
    rng = random.Random(seed)
    medians = [statistics.median(rng.choices(values, k=len(values))) for _ in range(10000)]
    return {"median": statistics.median(values),
            "bootstrap_95_percentile_interval": [percentile(medians, .025), percentile(medians, .975)]}


def median_optional(values: list[float | None]) -> float | None:
    observed = [value for value in values if value is not None]
    return statistics.median(observed) if observed else None


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def env_for(lane: str, account: pwd.struct_passwd) -> dict[str, str]:
    env = os.environ.copy()
    env.update({"HOME": account.pw_dir, "USER": account.pw_name, "LOGNAME": account.pw_name,
                "GOMAXPROCS": "1", "GOGC": "100",
                "DOTNET_gcServer": "0", "DOTNET_TieredCompilation": "1",
                "DOTNET_TieredPGO": "1", "DOTNET_ReadyToRun": "0",
                "DOTNET_GCHeapHardLimit": "02000000",
                "DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1",
                "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1"})
    if lane == "go":
        env["GOMEMLIMIT"] = "32MiB"
    elif lane == "dotnet":
        dotnet = os.environ.get("DOTNET") or shutil.which("dotnet") or "dotnet"
        resolved = Path(dotnet).resolve()
        env["DOTNET_ROOT"] = str(resolved.parent)
    return env


def base_command(lane: str) -> list[str]:
    if lane == "go":
        return [str(BIN / "sum-go")]
    if lane == "hotspot":
        java = os.environ.get("JAVA") or shutil.which("java") or "java"
        return [java, *JAVA_FLAGS, "-cp", str(BIN / "java"), "Sum"]
    if lane == "dotnet":
        dotnet = os.environ.get("DOTNET") or shutil.which("dotnet") or "dotnet"
        return [dotnet, str(BIN / "dotnet/ManagedBench.dll")]
    raise ValueError("невідомий managed runtime")


def drop_options(account: pwd.struct_passwd) -> dict:
    if os.geteuid() != 0:
        return {}
    return {"user": account.pw_uid, "group": account.pw_gid, "extra_groups": []}


def parse_time_stderr(data: bytes) -> tuple[int, float, float]:
    lines = data.decode("utf-8", errors="strict").splitlines()
    if lines and lines[0] == f"Command exited with non-zero status {EXPECTED}":
        lines.pop(0)
    if len(lines) != 1:
        raise ValueError("GNU time або workload вивів зайвий stderr: " + repr(data[:500]))
    match = re.fullmatch(r"MAXRSS_KIB=(\d+)\tUSER_SEC=([0-9.]+)\tSYS_SEC=([0-9.]+)", lines[0])
    if not match:
        raise ValueError("неправильний GNU time запис: " + repr(data[:500]))
    return int(match.group(1)), float(match.group(2)), float(match.group(3))


def parse_reply(line: str, count: int) -> dict:
    fields = line.rstrip("\n").split("\t")
    expected_checksum = (EXPECTED * count) & 255
    if (len(fields) != 5 or fields[0] != "OK" or fields[1] != str(count)
            or fields[2] != str(expected_checksum)):
        raise ValueError("хибна відповідь runtime: " + repr(line[:200]))
    if not all(part.isascii() and part.isdecimal() for part in fields[3:]):
        raise ValueError("нечислові лічильники GC: " + repr(line[:200]))
    return {"gc_count": int(fields[3]), "gc_pause_ms": int(fields[4])}


class WarmWorker:
    """Довгоживучий runtime-процес; один рядок stdin дає checksum у сталому сеансі."""
    def __init__(self, lane: str, account: pwd.struct_passwd, core: int):
        self.lane, self.account = lane, account
        command = ["taskset", "-c", str(core), *base_command(lane), "server", str(N)]
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, env=env_for(lane, account),
                                        start_new_session=True, **drop_options(account))
        try:
            os.sched_setaffinity(self.process.pid, {core})
        except OSError:
            self.close()
            raise

    def read_line(self) -> str:
        deadline = time.monotonic() + 60
        data = bytearray()
        fd = self.process.stdout.fileno()
        while b"\n" not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                raise TimeoutError(f"{self.lane}: немає відповіді протоколу")
            chunk = os.read(fd, 256)
            if not chunk:
                raise ValueError(f"{self.lane}: процес завершився без повної відповіді")
            data.extend(chunk)
            if len(data) > 1024:
                raise ValueError(f"{self.lane}: надмірна відповідь")
        if data.count(b"\n") != 1 or not data.endswith(b"\n"):
            raise ValueError(f"{self.lane}: додаткові байти протоколу")
        return data.decode("ascii")

    def request(self, count: int) -> dict:
        self.process.stdin.write(f"{count}\n".encode("ascii"))
        self.process.stdin.flush()
        return parse_reply(self.read_line(), count)

    def rss(self) -> dict:
        fields = {}
        for line in Path(f"/proc/{self.process.pid}/status").read_text().splitlines():
            if line.startswith(("VmHWM:", "VmRSS:")):
                key, value, *_ = line.split()
                fields[key.rstrip(":").lower() + "_kib"] = int(value)
        return fields

    def close(self) -> None:
        process = getattr(self, "process", None)
        if process is None or process.poll() is not None:
            return
        try:
            process.stdin.close()
            process.wait(timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            process.kill()
            process.wait()
        extra = process.stdout.read()
        errors = process.stderr.read()
        process.stdout.close()
        process.stderr.close()
        if process.returncode != 0 or extra or errors:
            raise ValueError(f"{self.lane}: завершення runtime: exit={process.returncode}, "
                             f"stdout={extra[:200]!r}, stderr={errors[:300]!r}")


def check_cold(lane: str, account: pwd.struct_passwd, core: int,
               timeout_seconds: float = 60) -> dict:
    command = ["taskset", "-c", str(core), "/usr/bin/time", "-f",
               "MAXRSS_KIB=%M\tUSER_SEC=%U\tSYS_SEC=%S", "--",
               *base_command(lane), "single", str(N)]
    started = time.monotonic_ns()
    result = subprocess.run(command, capture_output=True, timeout=timeout_seconds,
                            env=env_for(lane, account), **drop_options(account))
    elapsed = (time.monotonic_ns() - started) / 1e9
    if result.returncode != EXPECTED or result.stdout:
        raise ValueError(f"cold {lane}: exit={result.returncode}, stdout={result.stdout[:200]!r}, "
                         f"stderr={result.stderr[:500]!r}")
    rss_kib, user_cpu, system_cpu = parse_time_stderr(result.stderr)
    return {"elapsed_seconds": elapsed, "rss_kib": rss_kib,
            "user_cpu_seconds": user_cpu, "system_cpu_seconds": system_cpu}


def record_sample(path: Path, sample: dict, records: list[dict]) -> None:
    records.append(sample)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(sample, ensure_ascii=False, separators=(",", ":")) + "\n")
        stream.flush()


def sample_idle(zones, seconds: float, block: int, phase: str) -> dict:
    with rapl.Sampler(zones) as sampler:
        time.sleep(seconds)
    result = sampler.result()
    return {**result, "phase": phase, "block": block, "lane": "idle",
            "operations_per_program": 0, "process_cpu_seconds": 0.0,
            "rss_kib": None, "gc_count": 0, "gc_pause_ms": 0,
            "host_load_before": Path("/proc/loadavg").read_text().strip(),
            "temperatures": rapl.temperatures()}


def collect_jit_evidence(account: pwd.struct_passwd, core: int) -> dict:
    evidence = {"go": {"mode": "AOT compiler with Go runtime; no JIT"}}
    java_command = base_command("hotspot")
    java_command.insert(1, "-XX:+PrintCompilation")
    java = subprocess.run(["taskset", "-c", str(core), *java_command, "server", str(N)],
                          input="1\n" * 80, capture_output=True, timeout=120,
                          text=True, env=env_for("hotspot", account), **drop_options(account))
    java_text = java.stdout + java.stderr
    java_matches = [line for line in java_text.splitlines() if "Sum::sumToN" in line]
    if java.returncode != 0 or java.stdout.count("OK\t") != 80 or not java_matches:
        raise ValueError("JVM tiered JIT не підтверджено PrintCompilation: " + java_text[-1000:])
    evidence["hotspot"] = {"diagnostic": "-XX:+PrintCompilation", "compiled_loop_matches": java_matches[-8:]}

    dotnet_env = env_for("dotnet", account)
    dotnet_env["DOTNET_JitDisasm"] = "Program:SumToN"
    dotnet_env["DOTNET_JitDisasmSummary"] = "1"
    dotnet_env["DOTNET_JitStdOutFile"] = str(BIN / "dotnet-jit-diagnostic.txt")
    dotnet = subprocess.run(["taskset", "-c", str(core), *base_command("dotnet"), "server", str(N)],
                            input="1\n" * 80, capture_output=True, timeout=120,
                            text=True, env=dotnet_env, **drop_options(account))
    log_path = BIN / "dotnet-jit-diagnostic.txt"
    jit_text = (log_path.read_text(errors="replace") if log_path.exists() else "")
    if log_path.exists():
        log_path.unlink()
    if dotnet.returncode != 0 or dotnet.stdout.count("OK\t") != 80 or "SumToN" not in jit_text:
        raise ValueError(".NET JIT не підтверджено DOTNET_JitDisasm: " +
                         (dotnet.stdout + dotnet.stderr + jit_text)[-1200:])
    evidence["dotnet"] = {"diagnostic": "DOTNET_JitDisasm=Program:SumToN",
                          "disassembly_header": next((line.strip() for line in jit_text.splitlines()
                                                       if "Assembly listing for method" in line), "SumToN"),
                          "jit_log_sha256": hashlib.sha256(jit_text.encode()).hexdigest()}
    return evidence


def summarize_phase(samples: list[dict], phase: str, zones, lanes, rounds: int, seed: int) -> dict:
    summary = {}
    per_lane = {}
    phase_rows = [row for row in samples if row["phase"] == phase]
    idle_by_block = {row["block"]: row for row in phase_rows if row["lane"] == "idle"}
    for lane in lanes:
        rows = [row for row in phase_rows if row["lane"] == lane]
        wall_key = "elapsed_seconds" if phase == "cold" else "seconds"
        walls = [row[wall_key] for row in rows]
        item = {"samples": len(rows), "median_elapsed_seconds": statistics.median(walls),
                "p10_elapsed_seconds": percentile(walls, .1),
                "p90_elapsed_seconds": percentile(walls, .9),
                "median_process_cpu_seconds": statistics.median(row["process_cpu_seconds"] for row in rows),
                "median_peak_rss_kib": statistics.median(row["rss_kib"] for row in rows),
                "median_gc_count_delta": median_optional([row["gc_count"] for row in rows]),
                "median_gc_pause_ms_delta": median_optional([row["gc_pause_ms"] for row in rows]),
                "zones": {}}
        item["median_operations_per_second"] = (rows[0]["operations_per_program"] / item["median_elapsed_seconds"])
        if phase == "cold":
            item["median_user_cpu_seconds"] = statistics.median(row["user_cpu_seconds"] for row in rows)
            item["median_system_cpu_seconds"] = statistics.median(row["system_cpu_seconds"] for row in rows)
        paired = []
        paired_by_block = {}
        elapsed_by_block = {}
        for row in rows:
            idle = idle_by_block[row["block"]]
            active_seconds = row["seconds"]
            idle_rate = idle["energy_uj"]["package-0"] / idle["seconds"]
            adjusted_batch_joules = (row["energy_uj"]["package-0"] - idle_rate * active_seconds) / 1e6
            operations = row["operations_per_program"]
            paired.append(adjusted_batch_joules)
            paired_by_block[row["block"]] = adjusted_batch_joules / operations
            elapsed_by_block[row["block"]] = row[wall_key] / operations
        energy_ci = bootstrap_median(paired, seed + (0 if phase == "cold" else 1000) + lanes.index(lane))
        energy_ci.update({"p10_joules": percentile(paired, .1), "p90_joules": percentile(paired, .9),
                          "interpretation": "idle-scaled package diagnostic, not process energy"})
        item["paired_idle_scaled_package_joules"] = energy_ci
        for zone in zones:
            joules = [row["energy_uj"][zone.name] / 1e6 for row in rows]
            item["zones"][zone.name] = {"median_joules_per_sample": statistics.median(joules),
                                        "p10_joules": percentile(joules, .1),
                                        "p90_joules": percentile(joules, .9)}
        summary[lane] = item
        per_lane[lane] = {"idle_scaled_package_joules_per_operation": paired_by_block,
                          "elapsed_seconds_per_operation": elapsed_by_block}
    pairwise = {}
    for left_index, left in enumerate(lanes):
        for right_index in range(left_index + 1, len(lanes)):
            right = lanes[right_index]
            common_blocks = sorted(set(per_lane[left]["elapsed_seconds_per_operation"])
                                   & set(per_lane[right]["elapsed_seconds_per_operation"]))
            energy_differences = [per_lane[left]["idle_scaled_package_joules_per_operation"][block]
                                  - per_lane[right]["idle_scaled_package_joules_per_operation"][block]
                                  for block in common_blocks]
            elapsed_differences = [per_lane[left]["elapsed_seconds_per_operation"][block]
                                   - per_lane[right]["elapsed_seconds_per_operation"][block]
                                   for block in common_blocks]
            energy_summary = bootstrap_median(energy_differences,
                                              seed + 2000 + left_index * len(lanes) + right_index)
            elapsed_summary = bootstrap_median(elapsed_differences,
                                               seed + 3000 + left_index * len(lanes) + right_index)
            pairwise[f"{left}_minus_{right}"] = {
                "paired_blocks": len(common_blocks),
                "energy_joules_per_operation_difference": energy_summary,
                "elapsed_seconds_per_operation_difference": elapsed_summary,
                "sign_convention": "negative means the left lane has lower value",
                "energy_scope": "paired idle-scaled package diagnostic, not process energy"}
    summary["pairwise_differences"] = pairwise
    idle_rows = [row for row in phase_rows if row["lane"] == "idle"]
    summary["idle"] = {"samples": len(idle_rows), "median_elapsed_seconds": statistics.median(row["seconds"] for row in idle_rows),
                        "zones": {zone.name: {"median_joules_per_sample": statistics.median(
                            row["energy_uj"][zone.name] / 1e6 for row in idle_rows)} for zone in zones}}
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--rounds", type=int, default=30)
    parser.add_argument("--warmup", type=int, default=50)
    parser.add_argument("--batch-reps", type=int, default=50)
    parser.add_argument("--cold-batch-reps", type=int, default=10)
    parser.add_argument("--core", type=int, default=2)
    parser.add_argument("--seed", type=int, default=600)
    args = parser.parse_args()
    account_name = os.environ.get("SUDO_USER") if os.geteuid() == 0 else pwd.getpwuid(os.getuid()).pw_name
    if not account_name or account_name == "root":
        parser.error("запустіть звичайним користувачем або sudo з SUDO_USER")
    account = pwd.getpwnam(account_name)
    if not shutil.which("taskset") or not Path("/usr/bin/time").is_file():
        parser.error("потрібні taskset і GNU /usr/bin/time для фіксації affinity та RSS")
    if not (BIN / "sum-go").is_file() or not (BIN / "java/Sum.class").is_file() or not (BIN / "dotnet/ManagedBench.dll").is_file():
        parser.error("спершу запустіть build.sh")
    for lane in LANES:
        cold = check_cold(lane, account, args.core)
        if cold["elapsed_seconds"] <= 0 or cold["rss_kib"] <= 0:
            raise ValueError(f"неправильний cold профіль {lane}")
    native = subprocess.run([str(BIN / "sens-native.elf")], capture_output=True, timeout=15, check=False)
    if native.returncode != EXPECTED or native.stdout or native.stderr:
        raise ValueError("фізичний SENS D12 ELF не повернув код 173")

    workers = {}
    warmup = {}
    try:
        for lane in LANES:
            worker = workers[lane] = WarmWorker(lane, account, args.core)
            started = time.monotonic_ns()
            cpu_before = rapl.process_ticks(worker.process.pid)
            for _ in range(args.warmup):
                reply = worker.request(1)
                if reply["gc_count"] < 0 or reply["gc_pause_ms"] < 0:
                    raise ValueError("від'ємні GC лічильники")
            elapsed = (time.monotonic_ns() - started) / 1e9
            cpu_ticks = rapl.process_ticks(worker.process.pid) - cpu_before
            warmup[lane] = {"operations": args.warmup, "wall_seconds": elapsed,
                            "process_cpu_seconds": cpu_ticks / os.sysconf("SC_CLK_TCK"),
                            "rss": worker.rss()}
            # One additional request calibrates duration and still occurs before all measurements.
            reply = worker.request(args.batch_reps)
            if reply["gc_count"] < 0:
                raise ValueError("неправильний GC preflight")
        cold_pilots = [check_cold(lane, account, args.core)["elapsed_seconds"] for lane in LANES]
        idle_cold = statistics.median(cold_pilots) * args.cold_batch_reps
        warm_pilots = []
        for lane in LANES:
            before = time.monotonic_ns()
            workers[lane].request(args.batch_reps)
            warm_pilots.append((time.monotonic_ns() - before) / 1e9)
        idle_warm = statistics.median(warm_pilots)
        if args.check_only:
            print(f"MANAGED-D12-CHECK-PASS N={N} exit={EXPECTED} runtimes={len(LANES)}")
            return
        if args.rounds < 30 or args.warmup < 1 or args.batch_reps < 1 or args.cold_batch_reps < 1 or args.output is None:
            parser.error("потрібні >=30 блоків, додатний warm-up/batch і --output")
        output = args.output.resolve()
        samples_path = output.with_name(output.stem + ".samples.jsonl")
        if output.exists() or samples_path.exists():
            parser.error("звіт або raw JSONL уже існує")
        output.parent.mkdir(parents=True, exist_ok=True)
        samples_path.touch(exist_ok=False)
        if os.geteuid() == 0:
            os.chown(samples_path, account.pw_uid, account.pw_gid)
        zones = rapl.discover_zones("/sys/devices/virtual/powercap/intel-rapl")
        records = []
        rng = random.Random(args.seed)

        for phase, idle_seconds in (("cold", idle_cold), ("warm", idle_warm)):
            for block in range(args.rounds):
                order = [*LANES, "idle"]
                rng.shuffle(order)
                for lane in order:
                    load_before = Path("/proc/loadavg").read_text().strip()
                    busy_before = rapl.cpu_busy_ticks()
                    if lane == "idle":
                        with rapl.Sampler(zones) as sampler:
                            time.sleep(idle_seconds)
                        reading = sampler.result()
                        extra = {"elapsed_seconds": reading["seconds"], "process_cpu_seconds": 0.0,
                                 "rss_kib": None, "gc_count": 0, "gc_pause_ms": 0,
                                 "operations_per_program": 0, "user_cpu_seconds": 0.0,
                                 "system_cpu_seconds": 0.0}
                    elif phase == "cold":
                        command = ["taskset", "-c", str(args.core), "/usr/bin/time", "-f",
                                   "MAXRSS_KIB=%M\tUSER_SEC=%U\tSYS_SEC=%S", "--",
                                   *base_command(lane), "single", str(N)]
                        with rapl.Sampler(zones) as sampler:
                            started = time.monotonic_ns()
                            rss_values, user_values, system_values = [], [], []
                            for _ in range(args.cold_batch_reps):
                                usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
                                result = subprocess.run(command, capture_output=True, timeout=90,
                                                        env=env_for(lane, account), **drop_options(account))
                                usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
                                if result.returncode != EXPECTED or result.stdout:
                                    raise ValueError(f"cold {lane} збій: code={result.returncode}, "
                                                     f"out={result.stdout[:100]!r}, err={result.stderr[:300]!r}")
                                rss_kib, _, _ = parse_time_stderr(result.stderr)
                                user_cpu = usage_after.ru_utime - usage_before.ru_utime
                                system_cpu = usage_after.ru_stime - usage_before.ru_stime
                                rss_values.append(rss_kib)
                                user_values.append(user_cpu)
                                system_values.append(system_cpu)
                            elapsed = (time.monotonic_ns() - started) / 1e9
                        reading = sampler.result()
                        user_cpu, system_cpu = sum(user_values), sum(system_values)
                        extra = {"elapsed_seconds": elapsed, "process_cpu_seconds": user_cpu + system_cpu,
                                 "rss_kib": statistics.median(rss_values), "rss_max_kib": max(rss_values),
                                 "user_cpu_seconds": user_cpu, "system_cpu_seconds": system_cpu,
                                 "gc_count": None, "gc_pause_ms": None,
                                 "operations_per_program": args.cold_batch_reps}
                    else:
                        worker = workers[lane]
                        cpu_before = rapl.process_ticks(worker.process.pid)
                        started = time.monotonic_ns()
                        with rapl.Sampler(zones) as sampler:
                            stats = worker.request(args.batch_reps)
                        elapsed = (time.monotonic_ns() - started) / 1e9
                        reading = sampler.result()
                        cpu_after = rapl.process_ticks(worker.process.pid)
                        extra = {"elapsed_seconds": elapsed,
                                 "process_cpu_seconds": (cpu_after - cpu_before) / os.sysconf("SC_CLK_TCK"),
                                 "rss_kib": worker.rss().get("vmhwm_kib"),
                                 "gc_count": stats["gc_count"], "gc_pause_ms": stats["gc_pause_ms"],
                                 "operations_per_program": args.batch_reps,
                                 "user_cpu_seconds": None, "system_cpu_seconds": None}
                    sample = {**reading, **extra, "phase": phase, "block": block, "lane": lane,
                              "host_busy_ticks": rapl.cpu_busy_ticks() - busy_before,
                              "host_load_before": load_before, "temperatures": rapl.temperatures(),
                              "nominal_loop_iterations": 0 if lane == "idle" else N * extra["operations_per_program"]}
                    record_sample(samples_path, sample, records)
                print(f"{phase}: блок {block + 1}/{args.rounds}", flush=True)

        diagnostics = collect_jit_evidence(account, args.core)
        build_manifest_path = HERE / "toolchains.json"
        build_manifest = json.loads(build_manifest_path.read_text(encoding="utf-8"))
        zones = rapl.discover_zones("/sys/devices/virtual/powercap/intel-rapl")
        summaries = {phase: summarize_phase(records, phase, zones, LANES, args.rounds, args.seed)
                     for phase in ("cold", "warm")}
        try:
            authority_sha = subprocess.check_output(["git", "-C", str(ROOT / "external/sens"),
                                                     "rev-parse", "HEAD"], text=True).strip()
        except subprocess.CalledProcessError:
            authority_sha = "NOT_AVAILABLE"
        report = {
            "schema": "sens-managed-runtime-d12-loop/1",
            "scope": "COLD_PROCESS_AND_WARM_PERSISTENT_MANAGED_RUNTIME_PROFILE",
            "interpretation": "Go uses AOT plus its runtime; HotSpot and .NET use JIT. RAPL is package/zone energy, never per-process energy.",
            "workload": {"n": N, "physical_sens_native_exit_code": EXPECTED,
                         "managed_loop_checksum": EXPECTED, "cold_fresh_processes_per_sample": args.cold_batch_reps,
                         "warm_repetitions_per_request": args.batch_reps,
                         "warmup_operations_per_process": args.warmup,
                         "checksum_reply": "OK<TAB>repetitions<TAB>checksum<TAB>GC-count<TAB>GC-pause-ms"},
            "toolchains": build_manifest,
            "jit_evidence": diagnostics,
            "warmup": warmup,
            "summary": summaries,
            "protocol": {"rounds": args.rounds, "seed": args.seed, "cpu_affinity": [args.core],
                         "randomized_order_within_each_phase": True,
                         "idle_seconds_cold": idle_cold, "idle_seconds_warm": idle_warm,
                         "rapl_sample_period_seconds": .05},
            "provenance": {"wsm_source_sha": subprocess.check_output(["git", "-C", str(ROOT),
                         "rev-parse", "HEAD"], text=True).strip(),
                         "wsm_worktree": subprocess.check_output(["git", "-C", str(ROOT),
                         "status", "--short"], text=True).strip(),
                         "sens_authority_sha": authority_sha,
                         "kernel": os.uname().release, "machine": os.uname().machine,
                         "cpuinfo": Path("/proc/cpuinfo").read_text(),
                         "governor": Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").read_text().strip(),
                         "load_after": Path("/proc/loadavg").read_text().strip(),
                         "rapl_zones": [{"name": z.name, "path": str(z.path), "max_energy_uj": z.maximum} for z in zones],
                         "rapl_scope_note": "RAPL totals include all activity in each hardware zone; idle scaling is a diagnostic only."},
            "raw_samples": {"path": str(samples_path.relative_to(ROOT)), "sha256": sha256(samples_path),
                            "bytes": samples_path.stat().st_size, "records": len(records)},
            "limitations": ["one i5-6400 host", "one D12 loop", "Go is not JIT compiled",
                            "warm measurements include line protocol and reply printing",
                            "RAPL is not attributed to any process", "JIT warm-up is reported separately from steady requests"],
        }
        rapl.publish_report(output, report, (account.pw_uid, account.pw_gid) if os.geteuid() == 0 else None)
        print(json.dumps(summaries, ensure_ascii=False, indent=2))
    finally:
        errors = []
        for worker in workers.values():
            try:
                worker.close()
            except Exception as error:
                errors.append(str(error))
        if errors:
            raise ValueError("помилка завершення worker: " + "; ".join(errors))


if __name__ == "__main__":
    main()
