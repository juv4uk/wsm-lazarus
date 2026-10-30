#!/usr/bin/env python3
"""G6.104: однаковий фізичний D12 stdin для SENS ELF, C, Rust, FPC.

Вимір — тільки повний холодний запуск процесу з фізичним stdin/stdout.
Це НЕ warm loop, НЕ енергія, НЕ загальний рейтинг мов. Канон і свідки —
з pinned SENS/чинних FPC генераторів; host-код нижче є конкурентом,
а НЕ новим визначенням SENS чи викличним Dn dispatch.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import random
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PIN = "2c498b35af53c085450eac6f51b87facf7f9aa47"
LANGS = ("sens-elf", "c-gcc", "rust", "free-pascal")
NEGATIVE = (
    "overflow-up", "overflow-down", "overflow-wide", "empty", "short1",
    "short5", "extra", "invalid243", "badfirst", "badsecond", "badthird",
    "badlast", "newline", "projection", "d1",
)

# Host транспортує лише ратифікований T5M: base3, W5/W5/W2 і
# термінальне padding=2. Немає таблиць SENS функцій або D7 слів.
C_SOURCE = r"""
#include <stdint.h>
#include <unistd.h>
static int dec(unsigned char b, int width) {
    static const int d[5] = {81,27,9,3,1};
    int v=0;
    if (b>=243) return -1;
    for (int i=0;i<5;i++) {
        int t=(b/d[i])%3;
        if (i<width) { if (t>1) return -1; v=2*v+t; }
        else if (t!=2) return -1;
    }
    return v;
}
static unsigned char enc(int v,int width) {
    int r=0;
    for (int i=width-1;i>=0;i--) r=3*r+((v>>i)&1);
    for (int i=width;i<5;i++) r=3*r+2;
    return (unsigned char)r;
}
int main(void) {
    unsigned char raw[7],answer[3];
    if (read(0,raw,7)!=6) return 2;
    int value[2];
    for (int k=0;k<2;k++) {
        int a=dec(raw[3*k],5),b=dec(raw[3*k+1],5),
            c=dec(raw[3*k+2],2);
        if (a<0 || b<0 || c<0) return 2;
        int bits=(a<<7)|(b<<2)|c;
        value[k]=(bits&2048)?bits-4096:bits;
    }
    int sum=value[0]+value[1];
    if (sum < -2048 || sum > 2047) return 2;
    unsigned int bits=(unsigned int)sum&4095U;
    answer[0]=enc((int)(bits>>7),5);
    answer[1]=enc((int)((bits>>2)&31),5);
    answer[2]=enc((int)(bits&3),2);
    return write(1,answer,3)==3 ? 0 : 2;
}
"""

RUST_SOURCE = r"""
use std::io::{Read, Write};
fn dec(b:u8,width:usize)->Option<i32> {
    let d=[81,27,9,3,1]; let mut v=0i32;
    if b>=243 {return None;}
    for i in 0..5 {
        let t=((b as i32/d[i])%3) as i32;
        if i<width {if t>1{return None;} v=2*v+t;}
        else if t!=2 {return None;}
    }
    Some(v)
}
fn enc(v:u32,width:usize)->u8 {
    let mut b=0u32;
    for i in (0..width).rev(){b=3*b+((v>>i)&1);}
    for _ in width..5 {b=3*b+2;}
    b as u8
}
fn main(){
    let mut raw=[0u8;7];
    if std::io::stdin().read(&mut raw).unwrap_or(0)!=6 {
        std::process::exit(2);
    }
    let mut values=[0i32;2];
    for k in 0..2 {
        let a=dec(raw[k*3],5);
        let b=dec(raw[k*3+1],5);
        let c=dec(raw[k*3+2],2);
        if a.is_none() || b.is_none() || c.is_none(){
            std::process::exit(2);
        }
        let bits=(a.unwrap()<<7)|(b.unwrap()<<2)|c.unwrap();
        values[k]=if bits&2048!=0{bits-4096}else{bits};
    }
    let sum=values[0]+values[1];
    if !(-2048..=2047).contains(&sum){std::process::exit(2);}
    let bits=(sum as u32)&4095;
    let answer=[enc(bits>>7,5),enc((bits>>2)&31,5),enc(bits&3,2)];
    if std::io::stdout().write_all(&answer).is_err(){
        std::process::exit(2);
    }
}
"""

PASCAL_SOURCE = r"""
program konkurent_fizychnogo_d12;
{$mode objfpc}{$H+}
uses BaseUnix;
const D:array[0..4] of LongInt=(81,27,9,3,1);
var Raw:array[0..6] of Byte;
    Answer:array[0..2] of Byte;
    V:array[0..1] of LongInt;
    K,A,B,C,Bits,Sum,I,T,Value:LongInt;
function Dec(Value:Byte;W:LongInt):LongInt;
var J,Tr:LongInt;
begin
  Result:=0;
  if Value>=243 then Exit(-1);
  for J:=0 to 4 do begin
    Tr:=(Value div D[J]) mod 3;
    if J<W then begin
      if Tr>1 then Exit(-1);
      Result:=2*Result+Tr;
    end else if Tr<>2 then Exit(-1);
  end;
end;
function Enc(Value:LongInt;W:LongInt):Byte;
var J,R:LongInt;
begin
  R:=0;
  for J:=W-1 downto 0 do R:=3*R+((Value shr J) and 1);
  for J:=W to 4 do R:=3*R+2;
  Result:=Byte(R);
end;
begin
  if fpRead(0,Raw,7)<>6 then Halt(2);
  for K:=0 to 1 do begin
    A:=Dec(Raw[K*3],5);
    B:=Dec(Raw[K*3+1],5);
    C:=Dec(Raw[K*3+2],2);
    if (A<0) or (B<0) or (C<0) then Halt(2);
    Bits:=(A shl 7) or (B shl 2) or C;
    if (Bits and 2048)<>0 then V[K]:=Bits-4096 else V[K]:=Bits;
  end;
  Sum:=V[0]+V[1];
  if (Sum<-2048) or (Sum>2047) then Halt(2);
  Value:=Sum and 4095;
  Answer[0]:=Enc(Value shr 7,5);
  Answer[1]:=Enc((Value shr 2) and 31,5);
  Answer[2]:=Enc(Value and 3,2);
  if fpWrite(1,Answer,3)<>3 then Halt(2);
end.
"""


def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(exe: Path, frame: bytes, timeout: int = 5) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run([str(exe)], input=frame, capture_output=True,
                          check=False, timeout=timeout)


def validate(result: subprocess.CompletedProcess[bytes], expected: bytes) -> None:
    need(result.returncode == 0, "ненульовий код успішної форми")
    need(result.stderr == b"", "непорожня діагностика успішної форми")
    need(result.stdout == expected, "пошкоджено точний D12/T5M stdout")


def negative(result: subprocess.CompletedProcess[bytes]) -> None:
    need(result.returncode == 2, "неправильний код відмови")
    need(result.stdout == b"", "частковий stdout при негативі")


def selftest() -> None:
    good = subprocess.CompletedProcess(["self"], 0, b"\x01\x02\x03", b"")
    validate(good, b"\x01\x02\x03")
    rejects = 0
    for candidate in (
        subprocess.CompletedProcess(["self"], 1, good.stdout, b""),
        subprocess.CompletedProcess(["self"], 0, b"", b""),
        subprocess.CompletedProcess(["self"], 0, good.stdout, b"bad"),
        subprocess.CompletedProcess(["self"], 0, good.stdout+b"x", b""),
    ):
        try:
            validate(candidate, good.stdout)
        except ValueError:
            rejects += 1
    for candidate in (
        subprocess.CompletedProcess(["self"], 0, b"", b""),
        subprocess.CompletedProcess(["self"], 2, b"\xff", b""),
        subprocess.CompletedProcess(["self"], 3, b"", b""),
    ):
        try:
            negative(candidate)
        except ValueError:
            rejects += 1
    need(rejects == 7, "самотест не захистив код/байти/діагностику")


def build_hosts(root: Path, work: Path) -> dict[str, Path]:
    sources = work / "sources"
    outputs = work / "bin"
    sources.mkdir()
    outputs.mkdir()
    units = work / "units"
    units.mkdir()
    programs = {
        "c-gcc": ("c", C_SOURCE, ["gcc", "-std=c11", "-O2", "-Wall",
                                  "-Wextra", "-Werror"]),
        "rust": ("rs", RUST_SOURCE, ["rustc", "--edition=2021", "-C",
                                     "opt-level=2", "-C", "codegen-units=1"]),
        "free-pascal": ("pas", PASCAL_SOURCE,
                        ["fpc", "-B", "-O2", "-Mobjfpc", "-Cr", "-Co", "-Ci",
                         "-FU"+str(units), "-FE"+str(outputs)]),
    }
    result: dict[str, Path] = {}
    for name, (ext, code, command) in programs.items():
        path = sources / ("konkurent_d12_" + name.replace("-", "_") + "." + ext)
        executable = outputs / ("d12-" + name)
        path.write_text(code.strip() + "\n", encoding="utf-8")
        cmd = command + [str(path), "-o", str(executable)]
        if name == "free-pascal":
            cmd = command + ["-o"+executable.name, str(path)]
        p = subprocess.run(cmd, cwd=root, capture_output=True, timeout=180)
        need(p.returncode == 0, f"host build {name}: {p.stdout[-700:]!r} {p.stderr[-700:]!r}")
        need(executable.is_file(), "host binary відсутній " + name)
        result[name] = executable
    return result


def summarize(values: list[int]) -> dict[str, float | int]:
    need(len(values) >= 30 and all(v > 0 for v in values), "неповна матриця часу")
    v = sorted(values)
    return {
        "повторів": len(v),
        "медіана_мс": round(statistics.median(v) / 1_000_000, 6),
        "р95_мс": round(v[math.ceil(len(v)*.95)-1] / 1_000_000, 6),
        "мін_мс": round(v[0] / 1_000_000, 6),
        "макс_мс": round(v[-1] / 1_000_000, 6),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--fixtures", type=Path)
    parser.add_argument("--sens-elf", type=Path)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--repeat", type=int, default=30)
    parser.add_argument("--seed", type=int, default=104104)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    selftest()
    if args.selftest:
        print("D12-COLD-SELFTEST-OK negatives=7")
        return
    need(sys.platform == "linux" and platform.machine() == "x86_64",
         "потрібен Linux x86-64")
    need(30 <= args.repeat <= 100, "потрібно 30..100 перемішаних блоків")
    root = args.root.resolve()
    fixtures = args.fixtures.resolve()
    work = args.work.resolve()
    sens_elf = args.sens_elf.resolve()
    need((root/"external/sens/contracts/language-contract-12.lisp").is_file(),
         "немає закріпленого мовного контракту")
    need(sens_elf.is_file() and os.access(sens_elf, os.X_OK),
         "немає справжнього SENS ELF")
    need(not work.exists(), "цільова тека вже існує")
    work.mkdir(parents=True)
    manifest = (fixtures/"valid.tsv").read_text(encoding="utf-8").splitlines()
    need(len(manifest) == 13, "очікується 13 pinned фізичних пар")
    cases: dict[str, tuple[bytes, bytes]] = {}
    for row in manifest:
        name, left, right = row.split("\t")
        need(name not in cases and left and right, "дублікат/порожня форма")
        frame = (fixtures/(name+".frame")).read_bytes()
        answer = (fixtures/(name+"-expected.sens")).read_bytes()
        need(len(frame) == 6 and len(answer) == 3, "хибна ширина D12")
        cases[name] = (frame, answer)
    binaries = {"sens-elf": sens_elf, **build_hosts(root, work)}
    need(tuple(binaries.keys()) == LANGS, "неповні виконавці")
    for name, (frame, expected) in cases.items():
        for lang, exe in binaries.items():
            try:
                validate(invoke(exe, frame), expected)
            except ValueError as e:
                raise ValueError(f"попередній паритет {name}/{lang}: {e}") from e
    for name in NEGATIVE:
        frame = (fixtures/(name+".frame")).read_bytes()
        for lang, exe in binaries.items():
            try:
                negative(invoke(exe, frame))
            except ValueError as e:
                raise ValueError(f"негатив {name}/{lang}: {e}") from e
    hashes_before = {lang: sha(p) for lang, p in binaries.items()}
    for _ in range(3):
        for frame, expected in cases.values():
            for exe in binaries.values():
                validate(invoke(exe, frame), expected)
    order = [(name, lang) for name in cases for lang in LANGS]
    rng = random.Random(args.seed)
    measurements = []
    samples = {(name, lang): [] for name, lang in order}
    for block in range(args.repeat):
        rng.shuffle(order)
        for name, lang in order:
            frame, expected = cases[name]
            start = time.perf_counter_ns()
            result = invoke(binaries[lang], frame)
            elapsed = time.perf_counter_ns()-start
            validate(result, expected)
            need(elapsed > 0, "відсутній позитивний час")
            samples[(name, lang)].append(elapsed)
            measurements.append({
                "блок": block+1, "випадок": name, "виконавець": lang,
                "час_нс": elapsed, "вихід_SHA256": hashlib.sha256(result.stdout).hexdigest()
            })
    need(hashes_before == {lang: sha(p) for lang, p in binaries.items()},
         "бінарник змінився під час замірів")
    report = {
        "схема": "sens-d12-stdin-cold-compare/1",
        "час_utc": datetime.now(timezone.utc).isoformat(),
        "pinned_SENS_SHA": PIN,
        "контроль": "попередній pinned SENS REPL у профільному CI job",
        "межа": "cold-start процесу+stdin/read+число/CPU ADD+T5M/stdout, НЕ warm throughput",
        "енергія": "ENERGY_NOT_MEASURED",
        "застереження": "Host версії реалізують однакову вузьку D12 операцію і T5M, але startup, runtime і ABI різні; не рейтинг мов, не джоулі",
        "машина": {"OS": platform.platform(), "CPU": platform.processor(),
                   "Python": platform.python_version(), "arch": platform.machine()},
        "метод": {"seed": args.seed, "повторів": args.repeat, "прогрів": 3,
                  "порядок": "перемішано всі 13×4 форми в кожному блоці"},
        "виконувані_SHA256": hashes_before,
        "позитивів_перед_замірами": 13*4,
        "негативів_перед_замірами": len(NEGATIVE)*4,
        "сирі_виміри": measurements,
        "підсумки": {
            f"{name}/{lang}": summarize(values)
            for (name, lang), values in samples.items()
        },
    }
    need(len(measurements) == 52*args.repeat, "втрачені виміри")
    destination = work/"виміри.json"
    tmp = work/"виміри.json.tmp"
    with tmp.open("x", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2, allow_nan=False)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.link(tmp, destination)
    tmp.unlink()
    print(f"D12-COLD-OK binaries=4 cases=13 negatives=60 "
          f"runs={len(measurements)} energy=NOT-MEASURED")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.TimeoutExpired, IndexError) as exc:
        print("D12-COLD-BLOCK: " + str(exc), file=sys.stderr)
        raise SystemExit(2)
