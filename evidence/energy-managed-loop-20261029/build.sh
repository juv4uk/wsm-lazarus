#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
OUT="$ROOT/build/energy/managed-d12-loop"
GO=${GO:-go}
JAVAC=${JAVAC:-javac}
JAVA=${JAVA:-java}
DOTNET=${DOTNET:-dotnet}
FPC=${FPC:-fpc}
PYTHON=${PYTHON:-python3}
mkdir -p "$OUT/java" "$OUT/dotnet" "$OUT/fpc-units"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

"$PYTHON" - "$HERE" "$OUT" "$GO" "$JAVAC" "$JAVA" "$DOTNET" "$FPC" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

here, out = Path(sys.argv[1]), Path(sys.argv[2])
go, javac, java, dotnet, fpc = sys.argv[3:]


def run(name, command):
    started = time.monotonic_ns()
    result = subprocess.run(command, cwd=here, text=True, capture_output=True,
                            timeout=900, check=False)
    seconds = (time.monotonic_ns() - started) / 1e9
    if result.returncode:
        sys.stderr.write(result.stdout + result.stderr)
        raise SystemExit(f"{name}: exit={result.returncode}")
    return {"seconds": seconds, "command": command,
            "stdout": result.stdout[-2000:], "stderr": result.stderr[-2000:]}


go_version = subprocess.run([go, "version"], cwd=here, text=True, capture_output=True,
                             timeout=30, check=True).stdout.strip()
javac_version = subprocess.run([javac, "--version"], cwd=here, text=True, capture_output=True,
                               timeout=30, check=True).stdout.strip()
java_version = subprocess.run([java, "-version"], cwd=here, text=True, capture_output=True,
                              timeout=30, check=True).stderr.strip().splitlines()
dotnet_version = subprocess.run([dotnet, "--version"], cwd=here, text=True, capture_output=True,
                                timeout=30, check=True).stdout.strip()

builds = {}
builds["go"] = run("go build", [go, "build", "-trimpath", "-buildvcs=false",
                                   "-ldflags=-buildid=", "-o", str(out / "sum-go"),
                                   str(here / "sum.go")])
builds["java"] = run("javac", [javac, "--release", "21", "-d", str(out / "java"),
                                  str(here / "Sum.java")])
root = here.parents[1]
native_evidence = root / "evidence/energy-native-d12-loop-20261029"
for path in (out / "sens-native.elf", out / "sens-native.sens"):
    path.unlink(missing_ok=True)
builds["sens_native_baseline"] = run("FPC physical SENS D12 ELF", [fpc, "-B", "-Cr", "-Co", "-Ci",
        "-Mobjfpc", "-Fu" + str(root / "src"), "-FU" + str(out / "fpc-units"),
        "-FE" + str(out), "-obuild-sens-loop", str(native_evidence / "build-sens-loop.pas")])
run("publish SENS baseline", [str(out / "build-sens-loop"), str(out / "sens-native")])
os.chmod(out / "sens-native.elf", 0o755)
proj = here / "ManagedBench.csproj"
builds["dotnet_restore"] = run("dotnet restore", ["timeout", "300s", dotnet, "restore", str(proj),
        "--ignore-failed-sources", "--disable-parallel", "-p:RestoreIgnoreFailedSources=true"])
builds["dotnet_publish"] = run("dotnet publish", [dotnet, "publish", str(proj),
        "--configuration", "Release", "--no-restore", "--output", str(out / "dotnet"),
        "-p:UseAppHost=false", "-p:PublishReadyToRun=false"])

artifacts = [out / "sum-go", out / "java" / "Sum.class",
             out / "dotnet" / "ManagedBench.dll", out / "sens-native.elf"]
manifest = {
    "schema": "sens-managed-runtime-toolchains/1",
    "go": {"version": go_version, "build_flags": ["-trimpath", "-buildvcs=false", "-ldflags=-buildid="],
           "runtime_environment": {"GOMAXPROCS": "1", "GOGC": "100", "GOMEMLIMIT": "32MiB"},
           "artifact": artifacts[0].name},
    "java": {"javac_version": javac_version, "runtime_version": java_version,
             "compile_flags": ["--release", "21"], "runtime_flags": ["-Xms32m", "-Xmx32m", "-XX:+UseSerialGC", "-XX:+TieredCompilation", "-XX:ActiveProcessorCount=1"],
             "artifact": "java/Sum.class"},
    "dotnet": {"sdk_version": dotnet_version, "target_framework": "net10.0",
               "runtime_flags": {"DOTNET_gcServer": "0", "DOTNET_GCHeapHardLimit": "02000000", "DOTNET_TieredCompilation": "1", "DOTNET_TieredPGO": "1", "DOTNET_ReadyToRun": "0"},
               "build_flags": ["Release", "UseAppHost=false", "PublishReadyToRun=false"],
               "artifact": "dotnet/ManagedBench.dll"},
    "sens_native_baseline": {"kind": "existing narrow BuildD12SumLoopELF compiled from physical D24 T5M",
                             "source": "evidence/energy-native-d12-loop-20261029/build-sens-loop.pas",
                             "fpc_version": subprocess.run([fpc, "-iV"], cwd=here, text=True,
                                 capture_output=True, timeout=30, check=True).stdout.strip(),
                             "build_flags": ["-B", "-Cr", "-Co", "-Ci", "-Mobjfpc"],
                             "artifact": "sens-native.elf"},
    "builds": builds,
    "sources": [{"path": str(p.relative_to(root)),
                 "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in [here / "sum.go", here / "Sum.java", here / "Program.cs", proj,
                          native_evidence / "build-sens-loop.pas",
                          native_evidence / "count-d24.sens"]],
    "artifacts": [{"path": str(p.relative_to(out)), "bytes": p.stat().st_size,
                   "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in artifacts],
}
(out / "build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                encoding="utf-8")
(here / "toolchains.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                      encoding="utf-8")
print(json.dumps({"versions": {"go": go_version, "javac": javac_version,
      "java": java_version[0] if java_version else "", "dotnet": dotnet_version},
      "build_seconds": {k: v["seconds"] for k, v in builds.items()},
      "artifact_bytes": {item["path"]: item["bytes"] for item in manifest["artifacts"]}},
      ensure_ascii=False, indent=2))
PY
