#!/usr/bin/env python3
"""Відтворюване RAPL-вимірювання закріплених ядер SENS SSE2 та AVX2.

Вхід — точна upstream-директорія джерел і числові параметри навантаження;
`sens_root`/`root` мають тип `Path`, лічильники інтервалів — цілі мікроджоулі,
парна статистика лишається числами Python до серіалізації JSON. Кожен worker
володіє виділеними векторами протягом одного процесу; `Sampler` володіє
потоком/читаннями одного контекстного інтервалу. JSON спочатку пишеться в
тимчасові файли, синхронізується з диском і публікується без перезапису.

Питання: навіщо окремо закріплювати upstream SHA від мовного підмодуля?
Чому пакетний RAPL не приписує енергію worker-процесу? Навіщо перевіряти
числовий результат до початку вимірювань?
"""
import argparse
import hashlib
import json
import math
import os
import pwd
import random
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from measure import Sampler, counter_delta, discover_zones


SENS_SOURCE_SHA = "33f0c4d1ea812a09dd121bd15ed741241d5dbc65"
WSM_AUTHORITY_SHA = "2c498b35af53c085450eac6f51b87facf7f9aa47"
REPETITIONS_MIN = 30
BOOTSTRAP_SAMPLES = 20_000


def validate_source_sha(sha):
    if sha != SENS_SOURCE_SHA:
        raise ValueError(f"SHA джерела бенчмарка SENS не збігається: очікувався {SENS_SOURCE_SHA}, отримано {sha}")
    return True


def validate_authority_sha(sha):
    if sha != WSM_AUTHORITY_SHA:
        raise ValueError(
            f"SHA мовного авторитету WSM/SENS не збігається: очікувався {WSM_AUTHORITY_SHA}, отримано {sha}"
        )
    return True


def git_sha(root):
    return subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()


def parse_worker_output(text):
    lines = text.splitlines()
    if len(lines) != 1:
        raise ValueError("worker має вивести рівно один рядок результату")
    try:
        value = float(lines[0])
    except ValueError as error:
        raise ValueError("вивід worker не є одним числом із рухомою комою") from error
    if not math.isfinite(value):
        raise ValueError("результат worker не є скінченним числом")
    return value


def parse_dot_bench_output(text):
    values = {}
    for line in text.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            values[parts[0]] = parts[1]
    if "DOT_OK" not in text.splitlines() or "SUM_MISMATCH" in text:
        raise ValueError("upstream dot_bench не підтвердив числовий паритет")
    try:
        backend = values["BACKEND"]
        scalar = float(values["SCALAR_SUM"])
        avx2 = float(values["AVX2_SUM"])
    except (KeyError, ValueError) as error:
        raise ValueError("вивід upstream dot_bench неповний") from error
    if backend != "Avx2Fma" or not math.isfinite(scalar) or not math.isfinite(avx2):
        raise ValueError("upstream benchmark не виконав очікуваний скінченний шлях AVX2/FMA")
    return {"sse2": scalar, "avx2": avx2}


def build_worker(sens_root, build_dir, worker_source=None):
    sens_root, build_dir = Path(sens_root).resolve(), Path(build_dir).resolve()
    validate_source_sha(git_sha(sens_root))
    build_dir.mkdir(parents=True, exist_ok=True)
    assembly = sens_root / "crates/sens/src/machine_math_skylake.S"
    dot_bench = sens_root / "crates/sens/examples/dot_bench.rs"
    if not assembly.is_file() or not dot_bench.is_file():
        raise ValueError("немає закріплених upstream-джерел машинної математики")
    dot_source = dot_bench.read_text(encoding="utf-8")
    if "sens_dot_scalar" not in dot_source or "sens_dot_avx2" not in dot_source:
        raise ValueError("upstream dot_bench більше не викликає обидва фізичні ядра напряму")
    worker_source = Path(worker_source or Path(__file__).with_name("machine-math-worker.rs"))
    if not worker_source.is_file():
        raise FileNotFoundError(f"немає перевіреного джерела worker: {worker_source}")
    obj = build_dir / "machine_math_skylake.o"
    asm = subprocess.run(
        ["gcc", "-c", "-fPIC", "-march=skylake", str(assembly), "-o", str(obj)],
        text=True, capture_output=True, check=False,
    )
    if asm.returncode:
        raise RuntimeError("не вдалося зібрати асемблерне ядро: " + asm.stderr[-2000:])
    binaries = {}
    for kernel in ("sse2", "avx2"):
        binary = build_dir / f"machine-math-{kernel}"
        rust = subprocess.run(
            # Keep harness/setup code at the baseline ISA. The separately
            # assembled object contains the selected SSE2/AVX2 kernels.
            ["rustc", "--edition=2021", "-C", "opt-level=3", "-C", "target-cpu=x86-64",
             "-C", f"link-arg={obj}", str(worker_source), "-o", str(binary)],
            text=True, capture_output=True, check=False,
        )
        if rust.returncode:
            raise RuntimeError(f"не вдалося зібрати worker {kernel}: " + rust.stderr[-2000:])
        binaries[kernel] = binary
    return binaries


def run_dot_bench(sens_root, n, repetitions):
    return subprocess.check_output(
        ["cargo", "run", "--release", "--manifest-path",
         str(Path(sens_root) / "crates/sens/Cargo.toml"), "--example", "dot_bench", "--",
         str(n), str(repetitions)],
        cwd=sens_root, text=True, stderr=subprocess.STDOUT, timeout=600,
    )


def run_worker(binary, kernel, n, repetitions):
    result = subprocess.run(
        [str(binary), kernel, str(n), str(repetitions)],
        text=True, capture_output=True, check=False, timeout=600,
    )
    if result.returncode != 0 or result.stderr:
        raise RuntimeError(f"worker {kernel} завершився з помилкою ({result.returncode}): {result.stderr[-1000:]}")
    return parse_worker_output(result.stdout)


def verify_parity(binaries, sens_root, n, repetitions):
    reference = parse_dot_bench_output(run_dot_bench(sens_root, n, repetitions))
    observed = {kernel: run_worker(binary, kernel, n, repetitions)
                for kernel, binary in binaries.items()}
    for kernel in ("sse2", "avx2"):
        if not math.isclose(observed[kernel], reference[kernel], rel_tol=1e-12, abs_tol=1e-12):
            raise ValueError(f"{kernel} isolated worker differs from upstream dot_bench")
    return reference


def bootstrap_median_ci(values, seed, iterations=BOOTSTRAP_SAMPLES):
    if not values:
        raise ValueError("немає парних вимірів")
    rng = random.Random(seed)
    n = len(values)
    boot = [statistics.median(rng.choices(values, k=n)) for _ in range(iterations)]
    boot.sort()
    return [boot[int(0.025 * (iterations - 1))], boot[int(0.975 * (iterations - 1))]]


def summarize_pairs(pairs, seed=598):
    if len(pairs) < REPETITIONS_MIN:
        raise ValueError(f"потрібно щонайменше {REPETITIONS_MIN} парних блоків")
    blocks = [pair.get("block") for pair in pairs]
    if any(not isinstance(block, int) for block in blocks) or len(set(blocks)) != len(blocks):
        raise ValueError("ідентифікатори парних блоків мають бути унікальними цілими числами")
    required = ("sse2_package_uj", "avx2_package_uj", "idle_package_uj")
    for row in pairs:
        for key in required:
            if not isinstance(row.get(key), int) or row[key] <= 0:
                raise ValueError(f"некоректний приріст пакетного лічильника: {key}")
    elapsed_keys = ("sse2_elapsed_ns", "avx2_elapsed_ns", "idle_elapsed_ns")
    for row in pairs:
        for key in elapsed_keys:
            if not isinstance(row.get(key), int) or row[key] <= 0:
                raise ValueError(f"некоректна тривалість інтервалу RAPL: {key}")
    differences = [row["avx2_package_uj"] - row["sse2_package_uj"] for row in pairs]
    ci = bootstrap_median_ci(differences, seed)
    elapsed_differences = [row["avx2_elapsed_ns"] - row["sse2_elapsed_ns"] for row in pairs]
    elapsed_ci = bootstrap_median_ci(elapsed_differences, seed + 1)
    reductions_pct = [100.0 * (row["sse2_package_uj"] - row["avx2_package_uj"])
                      / row["sse2_package_uj"] for row in pairs]
    reduction_ci = bootstrap_median_ci(reductions_pct, seed + 2)
    return {
        "pairs": len(pairs),
        "median_sse2_package_uj": statistics.median(r["sse2_package_uj"] for r in pairs),
        "median_avx2_package_uj": statistics.median(r["avx2_package_uj"] for r in pairs),
        "median_idle_package_uj": statistics.median(r["idle_package_uj"] for r in pairs),
        "median_avx2_minus_sse2_package_uj": statistics.median(differences),
        "ci95_package_uj": ci,
        "ci_includes_zero": ci[0] <= 0 <= ci[1],
        "median_sse2_elapsed_ns": statistics.median(r["sse2_elapsed_ns"] for r in pairs),
        "median_avx2_elapsed_ns": statistics.median(r["avx2_elapsed_ns"] for r in pairs),
        "median_idle_elapsed_ns": statistics.median(r["idle_elapsed_ns"] for r in pairs),
        "median_avx2_minus_sse2_elapsed_ns": statistics.median(elapsed_differences),
        "ci95_elapsed_ns": elapsed_ci,
        "median_avx2_package_reduction_pct": statistics.median(reductions_pct),
        "ci95_package_reduction_pct": reduction_ci,
        "energy_scope": "інтервал пакета CPU; енергію не можна приписати одному процесу",
    }


def read_text_or_none(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def cpu_flags():
    for line in Path("/proc/cpuinfo").read_text().splitlines():
        if line.startswith("flags"):
            return set(line.split(":", 1)[1].split())
    return set()


def require_isa():
    required = {"avx2", "fma"}
    missing = required - cpu_flags()
    if missing:
        raise ValueError("ENERGY_NOT_MEASURED: хост не підтримує потрібні інструкції: " + ", ".join(sorted(missing)))


def child_identity():
    if os.geteuid() != 0:
        return {}
    username = os.environ.get("SUDO_USER")
    if not username:
        raise ValueError("запусти через sudo від звичайного користувача, щоб worker працював без root")
    account = pwd.getpwnam(username)
    if account.pw_uid == 0:
        raise ValueError("вимірювальний worker не повинен працювати від root")
    return {"user": account.pw_uid, "group": account.pw_gid, "extra_groups": []}


def prepare_worker_temp(path):
    """Дозволити unprivileged worker пройти тимчасового батька, створеного root.

    `path` — `pathlib.Path` до каталогу `TemporaryDirectory` з режимом 0700.
    Коли доступ до RAPL вимагає root, каталог передається власнику звичайного
    користувача до створення виконуваних workers. Він живе в контексті
    `TemporaryDirectory` і видаляється при виході; функція повертає `None` та
    не змінює права worker або RAPL.

    Питання: чому змінити власника треба до створення дочірніх каталогів?
    Чому worker усе одно має скидати root? Який контекст відповідає за cleanup?
    """
    if os.geteuid() == 0:
        identity = child_identity()
        os.chown(path, identity["user"], identity["group"])


def run_interval(argv, zones, core, parse_result=True):
    taskset = shutil.which("taskset")
    if not taskset:
        raise RuntimeError("для контрольованої прив'язки до CPU потрібен taskset")
    output, error = None, None
    start = time.monotonic_ns()
    with Sampler(zones) as sampler:
        proc = subprocess.Popen(
            [taskset, "-c", str(core), *map(str, argv)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, **child_identity(),
        )
        try:
            out, err = proc.communicate(timeout=600)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            raise TimeoutError("worker машинної математики перевищив межу 600 секунд")
        output, error = out.decode("ascii", errors="strict"), err.decode("utf-8", errors="replace")
        if proc.returncode != 0 or error:
            raise RuntimeError(f"worker завершився з кодом {proc.returncode}: {error[:1000]}")
    end = time.monotonic_ns()
    raw = sampler.result()
    if parse_result:
        value = parse_worker_output(output)
    else:
        value = None
    return {
        "output": output.strip(), "result": value, "wall_ns": end - start,
        "zone_delta_uj": raw["energy_uj"], "elapsed_ns": int(raw["seconds"] * 1e9),
        "counter_readings": raw["counter_readings"],
    }


def metadata(root, sens_root, args, binaries, zones):
    root, sens_root = Path(root).resolve(), Path(sens_root).resolve()
    validate_source_sha(git_sha(sens_root))
    validate_authority_sha(git_sha(root / "external/sens"))
    status = subprocess.check_output(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=normal"],
        text=True,
    )
    if status.strip():
        raise ValueError("робоче дерево джерел бенчмарка має бути чистим і закоміченим")
    env = {"schema": "wsm-machine-math-rapl/1", "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "workload": {"n": args.n, "repetitions": args.repetitions, "blocks": args.rounds,
                        "kernels": ["SSE2 sens_dot_scalar", "AVX2/FMA sens_dot_avx2"]},
           "source": {"repository": "https://github.com/juv4uk/sens", "sha": git_sha(sens_root),
                      "assembly": hashlib.sha256((sens_root / "crates/sens/src/machine_math_skylake.S").read_bytes()).hexdigest(),
                      "dot_bench": hashlib.sha256((sens_root / "crates/sens/examples/dot_bench.rs").read_bytes()).hexdigest(),
                      "worker": hashlib.sha256(Path(__file__).with_name("machine-math-worker.rs").read_bytes()).hexdigest()},
           "wsm": {"sha": subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
                   "authority_sha": subprocess.check_output(["git", "-C", str(root / "external/sens"), "rev-parse", "HEAD"], text=True).strip(),
                   "worktree_clean": True,
                   "measurement_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
           "host": {"cpu_model": next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
                    "kernel": os.uname().release, "flags": sorted(cpu_flags()), "affinity_core": args.core,
                    "governor_cpu0": read_text_or_none("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
                    "no_turbo": read_text_or_none("/sys/devices/system/cpu/intel_pstate/no_turbo"),
                    "loadavg_before": Path("/proc/loadavg").read_text().strip(),
                    "temperature_before": {str(p): p.read_text().strip() for p in Path("/sys/class/thermal").glob("thermal_zone*/temp")}},
           "toolchains": {"rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                          "gcc": subprocess.check_output(["gcc", "--version"], text=True).splitlines()[0],
                          "cargo": subprocess.check_output(["cargo", "--version"], text=True).strip(),
                          "zig": subprocess.check_output(["zig", "version"], text=True).strip()},
           "build_flags": {"assembly": "gcc -c -fPIC -march=skylake", "worker": "rustc --edition=2021 -C opt-level=3 -C target-cpu=x86-64"},
           "zones": [{"name": z.name, "path": str(z.path), "maximum_uj": z.maximum} for z in zones],
           "measurement_scope": "RAPL вимірює енергію всього пакета за інтервал; вона не приписується worker-процесу.",
           "artifacts": {kernel: hashlib.sha256(path.read_bytes()).hexdigest() for kernel, path in binaries.items()}}
    return env


def publish_pair(results_path, samples_path, report, samples, owner=None):
    results_path, samples_path = Path(results_path), Path(samples_path)
    if results_path.resolve() == samples_path.resolve():
        raise ValueError("results and samples artifact paths must be different")
    if results_path.exists() or samples_path.exists():
        raise FileExistsError("refusing to overwrite an existing benchmark artifact")
    parents = {results_path.parent, samples_path.parent}
    for parent in parents:
        parent.mkdir(parents=True, exist_ok=True)
        if owner is not None:
            os.chown(parent, *owner)
    report_bytes = (json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    sample_bytes = "".join(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n" for row in samples).encode()
    temps = []
    linked = []
    try:
        for path, data in ((results_path, report_bytes), (samples_path, sample_bytes)):
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                temps.append(stream.name)
                stream.write(data)
                stream.flush()
                if owner is not None:
                    os.fchown(stream.fileno(), *owner)
                os.fsync(stream.fileno())
        for temp, path in zip(temps, (results_path, samples_path)):
            os.link(temp, path)
            linked.append(path)
    except Exception:
        for path in linked:
            path.unlink(missing_ok=True)
        raise
    finally:
        for temp in temps:
            Path(temp).unlink(missing_ok=True)


def run_study(root, sens_root, args):
    require_isa()
    validate_source_sha(git_sha(sens_root))
    validate_authority_sha(git_sha(Path(root) / "external/sens"))
    zones = discover_zones("/sys/devices/virtual/powercap/intel-rapl")
    with tempfile.TemporaryDirectory(prefix="sens-machine-math-") as temp:
        prepare_worker_temp(Path(temp))
        binaries = build_worker(sens_root, Path(temp) / "bin")
        reference = verify_parity(binaries, sens_root, args.n, args.repetitions)
        meta = metadata(root, sens_root, args, binaries, zones)
        rng = random.Random(args.seed)
        samples, paired = [], {}
        for block in range(args.rounds):
            order = ["sse2", "avx2", "idle"]
            rng.shuffle(order)
            paired[block] = {"block": block}
            for position, label in enumerate(order):
                if label == "idle":
                    interval = run_interval(["/bin/true"], zones, args.core, parse_result=False)
                    package = interval["zone_delta_uj"][next(z.name for z in zones if z.name.startswith("package-"))]
                    paired[block]["idle_package_uj"] = package
                    paired[block]["idle_elapsed_ns"] = interval["elapsed_ns"]
                else:
                    interval = run_interval([binaries[label], label, args.n, args.repetitions], zones, args.core)
                    if not math.isclose(interval["result"], reference[label], rel_tol=1e-12, abs_tol=1e-12):
                        raise ValueError(f"результат {label} змінився у вимірювальному блоці {block}")
                    package = interval["zone_delta_uj"][next(z.name for z in zones if z.name.startswith("package-"))]
                    paired[block][f"{label}_package_uj"] = package
                    paired[block][f"{label}_elapsed_ns"] = interval["elapsed_ns"]
                samples.append({"block": block, "position": position, "condition": label,
                                "package_delta_uj": package, "interval": interval})
        summary = summarize_pairs(list(paired.values()), args.seed)
        report = {"metadata": meta, "correctness": {"dot_bench": reference, "worker_matches_dot_bench": True},
                  "summary": summary, "paired_blocks": list(paired.values()),
                  "interpretation": "Дослідницькі спостереження зони пакета; це не енергія процесу й не рейтинг мов."}
        owner = None
        if os.geteuid() == 0:
            account = pwd.getpwnam(os.environ["SUDO_USER"])
            owner = (account.pw_uid, account.pw_gid)
        publish_pair(args.results, args.samples, report, samples, owner)
        return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--sens-source", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--samples", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=30)
    parser.add_argument("--n", type=int, default=65536)
    parser.add_argument("--repetitions", type=int, default=4096)
    parser.add_argument("--core", type=int, default=2)
    parser.add_argument("--seed", type=int, default=598)
    parser.add_argument("--check-only", action="store_true", help="build and check parity without reading/reporting RAPL")
    args = parser.parse_args(argv)
    if args.rounds < REPETITIONS_MIN or args.n <= 0 or args.repetitions <= 0 or args.core < 0:
        parser.error("потрібно >=30 блоків і додатні обмежені значення навантаження/ядра CPU")
    if args.results.resolve() == args.samples.resolve():
        parser.error("шляхи результату та сирих зразків мають відрізнятися")
    sens_root = args.sens_source.resolve()
    root = args.root.resolve()
    validate_source_sha(git_sha(sens_root))
    validate_authority_sha(git_sha(root / "external/sens"))
    require_isa()
    if args.check_only:
        with tempfile.TemporaryDirectory(prefix="sens-machine-math-check-") as temp:
            binaries = build_worker(sens_root, Path(temp) / "bin")
            verify_parity(binaries, sens_root, args.n, args.repetitions)
        print("MACHINE-MATH-CORRECTNESS-OK source=33f0c4d1 sse2=matched avx2=matched ENERGY_NOT_MEASURED")
        return 0
    if args.results.exists() or args.samples.exists():
        parser.error("відмовляюся перезаписувати наявні артефакти бенчмарка")
    if os.geteuid() != 0:
        parser.error("апаратне вимірювання потребує доступу до RAPL; запусти через sudo від звичайного користувача")
    report = run_study(root, sens_root, args)
    print(json.dumps({"summary": report["summary"], "artifacts": [str(args.results), str(args.samples)]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
