#!/usr/bin/env python3
"""G6.170: 3 справжні D12/T5M програми, 25 фізичних кадрів, холодний старт.

Усе числове тут — host-контроль конкурентних компіляторів C/FPC, а не
новий мовний закон SENS. Семантика native ELF підтверджена pinned
Contract 12.0 і незалежним SENS oracle в уже злитому G6.161.
Профіль: signed D12, лише точна цілочисельна частка, D24 — fail-closed.
Вимірюється monotonic elapsed wall time окремого процесу; НЕ енергія,
НЕ прогрітий throughput, НЕ універсальний рейтинг мов.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import time

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
LANGS = ("sens-elf", "c-gcc", "free-pascal")
REQUIRED_NEGATIVES = (
    "divide-zero", "zero-zero", "fraction", "negative-fraction",
    "negative-divisor", "fraction-large", "promotion", "empty", "short1",
    "short5", "extra", "newline", "invalid243", "badfirst", "badsecond",
    "badlast", "projection", "d1",
)

# Обидва host-конкуренти читають 6 canonical T5M байтів, перевіряють
# КОЖЕН trit, знак D12, EOF і числові межі. Назва функції «частка»
# тут не використовується для вибору SENS операції; ці дві програми
# виключно контрольний конкурент нативному x86-64 ELF.
C_SOURCE = r"""
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
static int dec(unsigned char b,int width){
    const int weights[5]={81,27,9,3,1};
    int value=0;
    if(b>=243) return -1;
    for(int i=0;i<5;i++){
        int t=(b/weights[i])%3;
        if(i<width){if(t>1)return -1;value=2*value+t;}
        else if(t!=2)return -1;
    }
    return value;
}
static unsigned char enc(unsigned value,int width){
    unsigned result=0;
    for(int i=width-1;i>=0;i--)result=3*result+((value>>i)&1u);
    for(int i=width;i<5;i++)result=3*result+2u;
    return (unsigned char)result;
}
static int bad(void){
    static const char msg[]="D12 REJECT\n";
    ssize_t written=write(2,msg,sizeof(msg)-1);
    if(written<0)return 2;
    return 2;
}
int main(void){
    unsigned char input[7],answer[3];
    size_t got=0;
    while(got<6){
        ssize_t n=read(0,input+got,6-got);
        if(n<=0)return bad();
        got+=(size_t)n;
    }
    if(read(0,input+6,1)!=0)return bad();
    int signed_v[2];
    for(int k=0;k<2;k++){
        int a=dec(input[k*3],5),b=dec(input[k*3+1],5);
        int c=dec(input[k*3+2],2);
        if(a<0||b<0||c<0)return bad();
        int bits=(a<<7)|(b<<2)|c;
        signed_v[k]=(bits&2048)?bits-4096:bits;
    }
    if(signed_v[1]==0)return bad();
    if(signed_v[0]%signed_v[1]!=0)return bad();
    int quotient=signed_v[0]/signed_v[1];
    if(quotient < -2048 || quotient > 2047)return bad();
    unsigned bits=(unsigned)quotient&4095u;
    answer[0]=enc(bits>>7,5);
    answer[1]=enc((bits>>2)&31u,5);
    answer[2]=enc(bits&3u,2);
    return write(1,answer,3)==3 ? 0 : bad();
}
"""

FPC_SOURCE = r"""
{ G6.170 — конкурентний host D12 T5M, НЕ Pascal SENS evaluator. }
program kontrol_fizychnoi_chastky;
{$mode objfpc}{$H+}
uses BaseUnix;
const Weights:array[0..4] of LongInt=(81,27,9,3,1);
var Input:array[0..6] of Byte;
    Answer:array[0..2] of Byte;
    Values:array[0..1] of LongInt;
    K,A,B,C,Bits,Quotient,Filled,N:LongInt;

procedure Fail;
begin
  WriteLn(ErrOutput,'D12 REJECT');
  Halt(2);
end;

function Dec(Value:Byte;Width:LongInt):LongInt;
var J,Digit:LongInt;
begin
  Result:=0;
  if Value>=243 then Exit(-1);
  for J:=0 to 4 do begin
    Digit:=(LongInt(Value) div Weights[J]) mod 3;
    if J<Width then begin
      if Digit>1 then Exit(-1);
      Result:=2*Result+Digit;
    end else if Digit<>2 then Exit(-1);
  end;
end;

function Enc(Value:LongInt;Width:LongInt):Byte;
var J,R:LongInt;
begin
  R:=0;
  for J:=Width-1 downto 0 do R:=3*R+((Value shr J) and 1);
  for J:=Width to 4 do R:=3*R+2;
  Result:=Byte(R);
end;

begin
  Filled:=0;
  while Filled<6 do begin
    N:=FpRead(0,Input[Filled],6-Filled);
    if N<=0 then Fail;
    Inc(Filled,N);
  end;
  if FpRead(0,Input[6],1)<>0 then Fail;
  for K:=0 to 1 do begin
    A:=Dec(Input[K*3],5);
    B:=Dec(Input[K*3+1],5);
    C:=Dec(Input[K*3+2],2);
    if (A<0) or (B<0) or (C<0) then Fail;
    Bits:=(A shl 7) or (B shl 2) or C;
    if (Bits and 2048)<>0 then Values[K]:=Bits-4096
    else Values[K]:=Bits;
  end;
  if Values[1]=0 then Fail;
  if Values[0] mod Values[1]<>0 then Fail;
  Quotient:=Values[0] div Values[1];
  if (Quotient< -2048) or (Quotient>2047) then Fail;
  Bits:=Quotient and 4095;
  Answer[0]:=Enc(Bits shr 7,5);
  Answer[1]:=Enc((Bits shr 2) and 31,5);
  Answer[2]:=Enc(Bits and 3,2);
  if FpWrite(1,Answer,3)<>3 then Halt(2);
end.
"""


def need(value: bool, explanation: str) -> None:
    if not value:
        raise ValueError(explanation)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_command(
    argv: list[str], *, data: bytes | None = None, timeout: int = 10,
    cwd: Path | None = None,
) -> tuple[int, bytes, bytes, int]:
    start = time.perf_counter_ns()
    process = subprocess.run(
        argv, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, cwd=cwd, check=False,
    )
    elapsed = time.perf_counter_ns() - start
    return process.returncode, process.stdout, process.stderr, elapsed


def must_match(code: int, answer: bytes, stderr: bytes, expected: bytes) -> None:
    need(code == 0, f"невдале виконання: exit={code}, stderr={stderr[:120]!r}")
    need(not stderr, f"побічний stderr на успіху: {stderr[:120]!r}")
    need(answer == expected, "непобайтовий T5M результат або неправильна довжина")


def must_reject(code: int, answer: bytes, stderr: bytes) -> None:
    need(code == 2, f"негатив має повернути exit2, отримано {code}")
    need(answer == b"", "негатив опублікував частковий stdout")
    need(bool(stderr), "негатив не повідомив про відмову")


def summary(samples: list[int]) -> dict[str, float | int]:
    need(len(samples) >= 10 and all(t > 0 for t in samples),
         "мінімум 10 повних додатних вимірів")
    ordered = sorted(samples)
    return {
        "кількість": len(ordered),
        "медіана_мс": round(statistics.median(ordered) / 1_000_000, 6),
        "р95_мс": round(ordered[math.ceil(.95 * len(ordered)) - 1] / 1_000_000, 6),
        "мін_мс": round(ordered[0] / 1_000_000, 6),
        "макс_мс": round(ordered[-1] / 1_000_000, 6),
    }


def selftest() -> int:
    rejected = 0
    for example in (
        (2, b"\x12", b"bad", b"\x12"),
        (0, b"", b"", b"\x12"),
        (0, b"\x12\x00", b"", b"\x12"),
        (0, b"\x12", b"bad", b"\x12"),
    ):
        try:
            must_match(*example)
        except ValueError:
            rejected += 1
    for example in (
        (0, b"", b"bad"),
        (2, b"\x12", b"bad"),
        (2, b"", b""),
        (1, b"", b"bad"),
    ):
        try:
            must_reject(*example)
        except ValueError:
            rejected += 1
    for data in ([], [1] * 9, [1] * 9 + [0]):
        try:
            summary(data)
        except ValueError:
            rejected += 1
    need(rejected == 11, "самоперевірка не зупинила всі підміни")
    return rejected


def build_baselines(work: Path, root: Path) -> dict[str, Path]:
    sources = work / "джерела"
    binaries = work / "двійкові"
    sources.mkdir()
    binaries.mkdir()
    c_path = sources / "контроль.c"
    fpc_path = sources / "контроль.pas"
    c_path.write_text(C_SOURCE, encoding="utf-8")
    fpc_path.write_text(FPC_SOURCE, encoding="utf-8")
    c_bin = binaries / "контроль-c"
    fpc_bin = binaries / "контроль-fpc"
    for command in (
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
         str(c_path), "-o", str(c_bin)],
        ["fpc", "-B", "-O2", "-Mobjfpc", "-Fu" + str(root / "src"),
         "-FU" + str(work), "-FE" + str(binaries), "-oконтроль-fpc",
         str(fpc_path)],
    ):
        code, stdout, stderr, _ = run_command(command, timeout=180, cwd=root)
        need(code == 0, f"конкурент не скомпільований: {command[0]}, "
                        f"stdout={stdout[-1200:]!r}, stderr={stderr[-1200:]!r}")
    need(c_bin.is_file() and fpc_bin.is_file(), "бракує виконуваного конкурента")
    return {"c-gcc": c_bin, "free-pascal": fpc_bin}


def fixtures(folder: Path) -> tuple[list[tuple[str, bytes, bytes]], list[tuple[str, bytes]]]:
    manifest = folder / "cases.tsv"
    need(manifest.is_file(), "немає фізичних свідків G6.161")
    positives: list[tuple[str, bytes, bytes]] = []
    for line in manifest.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        need(len(fields) == 4, "пошкоджено manifest")
        name = fields[0]
        need(name.isascii() and name.isdigit() and len(name) == 2,
             "неочікуваний контрольний номер")
        source = folder / (name + ".frame")
        wanted = folder / (name + ".expected.sens")
        proof = folder / (name + ".sens")
        need(proof.is_file(), "зникло канонічне джерело .sens")
        raw = source.read_bytes()
        expected = wanted.read_bytes()
        need(len(raw) == 6 and len(expected) == 3, "втрачено фізичну ширину W12")
        positives.append((name, raw, expected))
    need(len(positives) == 25 and len(set(x[0] for x in positives)) == 25,
         "позитивів має бути рівно 25 без повторів")
    negatives = []
    for name in REQUIRED_NEGATIVES:
        p = folder / (name + ".frame")
        need(p.is_file(), "відсутній негативний фізичний кадр: " + name)
        negatives.append((name, p.read_bytes()))
    need(len(negatives) == 18, "бракує фізичних негативів")
    return positives, negatives


def measure(args: argparse.Namespace) -> dict[str, object]:
    need(platform.system() == "Linux" and platform.machine() == "x86_64",
         "тест призначений лише для Linux x86-64")
    need(10 <= args.repeat <= 50, "між 10 і 50 повних повторів")
    need(0 <= args.seed <= 2**31 - 1, "неправильне детерміноване зерно")
    root = args.root.resolve()
    work = args.work.resolve()
    need(not work.exists(), "каталог вимірювання вже існує; відмова від перезапису")
    native = args.sens_elf.resolve()
    need(native.is_file() and os.access(native, os.X_OK),
         "немає справжнього виконуваного SENS ELF")
    work.mkdir(parents=True)
    baselines = build_baselines(work, root)
    executables = {"sens-elf": native, **baselines}
    positives, negatives = fixtures(args.fixtures)
    for language, path in executables.items():
        for name, frame, expected in positives:
            code, answer, stderr, _ = run_command([str(path)], data=frame)
            must_match(code, answer, stderr, expected)
        for name, frame in negatives:
            code, answer, stderr, _ = run_command([str(path)], data=frame)
            must_reject(code, answer, stderr)
    # Відокремлюємо перевірки correctness/negative від вимірювань.
    # Seed/round порядок — відтворюваний протокол, НЕ тотожний час.
    rng = random.Random(args.seed)
    observations: list[dict[str, str | int]] = []
    timings: dict[str, list[int]] = {lang: [] for lang in LANGS}
    for round_no in range(args.repeat):
        sample = positives[:]
        rng.shuffle(sample)
        for name, frame, expected in sample:
            languages = list(LANGS)
            rng.shuffle(languages)
            for language in languages:
                code, out, err, elapsed = run_command(
                    [str(executables[language])], data=frame
                )
                must_match(code, out, err, expected)
                need(elapsed > 0, "монотонний секундомір не дав часу")
                observations.append({
                    "раунд": round_no + 1,
                    "випадок": name,
                    "виконавець": language,
                    "час_нс": elapsed,
                })
                timings[language].append(elapsed)
    need(len(observations) == args.repeat * len(positives) * len(LANGS),
         "пропущено виміри")
    results: dict[str, object] = {
        "схема": "sens-d5-chastka-cold/1",
        "pinned_sens": PIN,
        "профіль": "D5:10111 дві signed D12, лише цілі D12; 6 байтів T5M stdin",
        "середовище": {"система": platform.platform(), "машина": platform.machine()},
        "режим": "cold-start весь процес включно з фізичним stdin/stdout",
        "метод": "perf_counter_ns; парне рандомізоване чергування; без прогріву",
        "зерно": args.seed,
        "повторів_на_випадок": args.repeat,
        "позитивів_перед_замірами": len(positives) * len(LANGS),
        "негативів_перед_замірами": len(negatives) * len(LANGS),
        "сирі_виміри": observations,
        "підсумки": {lang: summary(timings[lang]) for lang in LANGS},
        "виконувані_SHA256": {lang: sha256(path) for lang, path in executables.items()},
        "виконувані_розміри": {lang: path.stat().st_size for lang, path in executables.items()},
        "енергія": "ENERGY_NOT_MEASURED",
        "попередження": (
            "Час холодного запуску, не throughput і не джоулі. "
            "Компілятори й компонування різні; не робити рейтингу швидкодії мов. "
            "Коректність native окремо доведена pinned SENS REPL у G6.161."
        ),
    }
    report = work / "виміри.json"
    staged = work / "виміри.json.partial"
    staged.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    os.replace(staged, report)
    print("Д5-ЧАСТКА-COLD-ГОТОВО binaries=3 cases=25 negatives=54 "
          f"runs={len(observations)} energy=NOT_MEASURED")
    return results


def main() -> int:
    p = argparse.ArgumentParser(description="G6.170: bounded cold-start фізична D5 частка")
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--root", type=Path)
    p.add_argument("--fixtures", type=Path)
    p.add_argument("--sens-elf", type=Path)
    p.add_argument("--work", type=Path)
    p.add_argument("--repeat", type=int, default=20)
    p.add_argument("--seed", type=int, default=170170)
    args = p.parse_args()
    try:
        if args.selftest:
            print(f"Д5-ЧАСТКА-COLD-САМОТЕСТ негативів={selftest()}")
            return 0
        need(all(v is not None for v in
                 (args.root, args.fixtures, args.sens_elf, args.work)),
             "потрібні --root --fixtures --sens-elf --work")
        measure(args)
        return 0
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        print("Д5-ЧАСТКА-COLD-ВІДМОВА: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
