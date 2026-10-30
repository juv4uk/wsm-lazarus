#!/usr/bin/env python3
"""G6.179: детермінований фізичний мутаційний тест наявного T5M→WideIR→ELF64.

Не є мовним оракулом: прийняті мутовані форми перевіряються як справжній
машинний ELF, а не як очікуваний SENS-результат. Жодної проєкції за іменем.
"""
from __future__ import annotations

import argparse
import hashlib
import random
import subprocess
import sys
import tempfile
from pathlib import Path

MODE = "--скомпілювати-фізичний-потік"
DIAGNOSTIC = "ШИРОКИЙ-ПОТІК-ВІДМОВА:".encode("utf-8")
SEED = 0x6_179_2026
MUTATION_COUNT = 128 + 64 + 32 + 32 + 3


def demand(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def command(argv: list[str], *, input_bytes: bytes | None = None,
            timeout: int = 5) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(argv, input=input_bytes, capture_output=True,
                              timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Перевищено ліміт виконання: {argv[0]}") from exc


def compile_physical(exe: Path, source: bytes, title: str) -> tuple[int, bytes]:
    outcome = command([str(exe), MODE], input_bytes=source)
    demand(outcome.returncode in (0, 2),
           f"{title}: неприпустиме завершення компілятора {outcome.returncode}")
    if outcome.returncode == 2:
        demand(outcome.stdout == b"", f"{title}: після відмови витік часткового ELF")
        demand(DIAGNOSTIC in outcome.stderr,
               f"{title}: відсутня українська діагностика відмови")
    else:
        demand(outcome.stdout.startswith(b"\x7fELF"),
               f"{title}: успіх без фізичного ELF")
        demand(120 < len(outcome.stdout) < 65536,
               f"{title}: неприйнятний розмір ELF: {len(outcome.stdout)}")
    return outcome.returncode, outcome.stdout


def run_elf(image: bytes, place: Path, title: str) -> bytes:
    path = place / "виконуваний.elf"
    path.write_bytes(image)
    path.chmod(0o700)
    header = command(["readelf", "-h", str(path)])
    demand(header.returncode == 0 and b"Type:" in header.stdout
           and b"DYN" in header.stdout
           and b"Advanced Micro Devices X86-64" in header.stdout,
           f"{title}: невірний ELF64 x86-64 PIE")
    headers = command(["readelf", "-l", str(path)])
    demand(headers.returncode == 0 and b"LOAD" in headers.stdout
           and b"INTERP" not in headers.stdout
           and b"DYNAMIC" not in headers.stdout,
           f"{title}: сторонній завантажувач або неповний PT_LOAD")
    result = command([str(path)], timeout=4)
    demand(result.returncode == 0 and result.stderr == b"",
           f"{title}: ELF не виконався правильно: {result.returncode}")
    demand(0 < len(result.stdout) <= 65536,
           f"{title}: машинний вихід порожній або поза межею")
    return result.stdout


def make_mutations(sources: list[bytes]) -> list[tuple[str, bytes]]:
    rng = random.Random(SEED)
    result: list[tuple[str, bytes]] = []
    for n in range(128):
        data = bytearray(sources[n % len(sources)])
        pos = rng.randrange(len(data))
        data[pos] ^= 1 << rng.randrange(8)
        result.append((f"зміна-біта-{n:03d}", bytes(data)))
    for n in range(64):
        length = rng.randrange(65)
        result.append((f"довільні-байти-{n:03d}", rng.randbytes(length)))
    for n in range(32):
        src = sources[n % len(sources)]
        result.append((f"неповне-слово-{n:03d}", src[:rng.randrange(len(src))]))
    for n in range(32):
        src = sources[n % len(sources)]
        result.append((f"зайвий-хвіст-{n:03d}",
                       src + rng.randbytes(1 + rng.randrange(9))))
    result.extend([
        ("українська-текстова-проєкція", "(нуль? 0)\n".encode("utf-8")),
        ("надмірний-фізичний-потік", b"\x00" * 65537),
        ("неканонічні-байти", b"\xff" * 32),
    ])
    demand(len(result) == MUTATION_COUNT, "порушено кількість мутацій")
    demand(len({source for _, source in result}) >= 190,
           "мутаційний набір утратив різноманітність")
    return result


def main() -> int:
    p = argparse.ArgumentParser(description="Фізичні мутації T5M→ELF64")
    p.add_argument("--компілятор", required=True, type=Path)
    p.add_argument("--свідки", required=True, type=Path)
    a = p.parse_args()
    exe = a.компілятор.resolve()
    fixtures = a.свідки.resolve()
    demand(exe.is_file(), "немає зібраного FPC компілятора")
    demand((fixtures / "cases.tsv").is_file(), "немає фізичного маніфесту")
    sources = [(fixtures / f"{i:02d}.sens").read_bytes()
               for i in range(1, 17)]
    demand(all(sources), "порожній pinned фізичний свідок")
    mutations = make_mutations([sources[i] for i in (0, 8, 15)])
    digest = hashlib.sha256()
    for title, source in mutations:
        digest.update(len(source).to_bytes(4, "little"))
        digest.update(source)
    rejected = accepted = 0
    with tempfile.TemporaryDirectory(prefix="sens-g6-179-") as tmp:
        place = Path(tmp)
        # 16 базових справжніх ELF з уже наявних фізичних fixtures.
        for i, source in enumerate(sources, 1):
            title = f"базовий-{i:02d}"
            rc, image = compile_physical(exe, source, title)
            demand(rc == 0, f"{title}: зламано вихідну позитивну програму")
            actual = run_elf(image, place, title)
            expected = (fixtures / f"{i:02d}.expected.sens").read_bytes()
            demand(actual == expected, f"{title}: машинний вихід не збігся")
        original_rc, original = compile_physical(exe, sources[8], "до-мутацій")
        demand(original_rc == 0, "не зібрано контрольний ELF")

        for title, source in mutations:
            rc, image = compile_physical(exe, source, title)
            if rc == 2:
                rejected += 1
            else:
                accepted += 1
                run_elf(image, place, title)

        final_rc, final = compile_physical(exe, sources[8], "після-мутацій")
        demand(final_rc == 0 and final == original,
               "мутаційна перевірка змінила контрольні байти ELF")
        demand(rejected > 0, "відсутні відмови для пошкоджених слів")
        demand(accepted + rejected == MUTATION_COUNT,
               "не всі випадки отримали завершення")
    print(f"МУТАЦІЇ-WIDEIR-ELF-ГАРАЗД базових-ELF=16 мутацій={MUTATION_COUNT} "
          f"відмов={rejected} прийнятих-ELF={accepted} "
          f"відновлено=так sha256-набору={digest.hexdigest()} "
          "семантичний-оракул=НЕ_ВИКОНАНО енергія=НЕ_ВИМІРЯНА")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, FileNotFoundError, OSError) as error:
        print(f"МУТАЦІЇ-WIDEIR-ELF-ПРОВАЛ: {error}", file=sys.stderr)
        sys.exit(1)
