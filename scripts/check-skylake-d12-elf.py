#!/usr/bin/env python3
"""G6.75 — атестація ТІЛЬКИ 15 байтів реального ADD D12 ELF64.
ISA/inventory pinned SENS визначає фізичні можливості, не закони мови.
AVX/AVX2 не виконуємо: наявність у CPU каталозі не замінює CPUID/XGETBV.
"""
from __future__ import annotations
import argparse
import pathlib
import struct
import sys


class EIsa(ValueError):
    pass


def need(ok: bool, message: str) -> None:
    if not ok:
        raise EIsa(message)


def profile(inventory: str, cpu: str) -> None:
    def rows(src: str) -> list[str]:
        return [s.strip() for s in src.splitlines()
                if s.strip() and not s.lstrip().startswith(";")]
    a, b = rows(inventory), rows(cpu)
    for row in (
        "(skylake-client-inventory-1",
        "(cpu intel-core-i5-6400)",
        "(profile-class client)",
        "(admission-policy fail-closed)",
        "(admitted-extension X86-BASE)",
        "(admitted-extension X86-64)",
        "(runtime-gated-extension AVX cpuid-avx+osxsave+xgetbv-xmm-ymm)",
        "(runtime-gated-extension AVX2 cpuid-avx2+avx-state)",
        "(unavailable-extension AVX-512)",
        "(unavailable-extension AMX)",
    ):
        need(a.count(row) == 1, "порушено pinned ISA inventory: " + row)
    need("(admitted-extension AVX-512)" not in a and
         "(admitted-extension AMX)" not in a, "підроблено клієнтську ISA")
    for row in (
        "(cpu-profile-1", "(cpu intel-core-i5-6400)",
        "(isa x86-64)", "(runtime-feature-check required)",
        "(avx-state-check xgetbv-required)",
        "(unavailable-extension AVX-512)",
        "(gated-extension AVX (gate cpuid-avx+osxsave+xgetbv-xmm-ymm))",
    ):
        need(b.count(row) == 1, "порушено pinned CPU profile: " + row)


def field(image: bytes, pos: int, size: int) -> int:
    need(0 <= pos <= len(image)-size, "ELF поле за фізичною межею")
    return int.from_bytes(image[pos:pos+size], "little")


def check(image: bytes, left: int, right: int, inventory: str, cpu: str) -> None:
    profile(inventory, cpu)
    # left/right — лише host свідки з існуючого FPC генератора .sens.
    # Вони не створюють домен чи SENS закон; це порівняння immediates.
    need(type(left) is int and type(right) is int and
         -2048 <= left <= 2047 and -2048 <= right <= 2047,
         "тестові операнди не належать діапазону signed D12")
    need(150 <= len(image) <= 8192, "неповний або завеликий ELF")
    need(image[:7] == b"\x7fELF\x02\x01\x01", "не ELF64 little-endian")
    for pos, size, value in (
        (16, 2, 3), (18, 2, 62), (20, 4, 1),
        (24, 8, 120), (32, 8, 64), (52, 2, 64),
        (54, 2, 56), (56, 2, 1), (64, 4, 1),
        (68, 4, 5), (72, 8, 0), (80, 8, 0),
        (88, 8, 0), (96, 8, len(image)),
        (104, 8, len(image)), (112, 8, 4096),
    ):
        need(field(image, pos, size) == value,
             f"порушено ELF64 ET_DYN/PIE/RX поле {pos}")
    prelude = (b"\xb8" + struct.pack("<i", left) +
               b"\x05" + struct.pack("<i", right) +
               b"\x25\xff\x0f\x00\x00")
    need(image[120:135] == prelude,
         "підміна MOV EAX / ADD EAX / AND EAX,0xfff")
    need(image[135:140] != b"\x00"*5, "обірвано машинний шлях після ADD")


def negative_tests(image: bytes, left: int, right: int,
                   inventory: str, cpu: str) -> int:
    count = 0
    def negative(label: str, body: bytes, l: int, r: int,
                 inv: str, spec: str) -> None:
        nonlocal count
        try:
            check(body, l, r, inv, spec)
        except EIsa:
            count += 1
        else:
            raise EIsa("тест прийняв підробку: " + label)
    # Перевіряти саме вже скомпільований реальний ELF, а не toy header.
    for pos in (0, 4, 16, 18, 20, 24, 32, 52, 54, 56,
                64, 68, 80, 88, 96, 104, 112, 120, 125, 130):
        bad = bytearray(image)
        bad[pos] ^= 0xff
        negative(f"зіпсований байт {pos}", bytes(bad),
                 left, right, inventory, cpu)
    negative("truncated", image[:119], left, right, inventory, cpu)
    negative("appended", image+b"x", left, right, inventory, cpu)
    negative("left", image, left+1, right, inventory, cpu)
    negative("right", image, left, right-1, inventory, cpu)
    negative("AVX without XGETBV", image, left, right,
             inventory.replace(
                 "(runtime-gated-extension AVX cpuid-avx+osxsave+xgetbv-xmm-ymm)",
                 "(runtime-gated-extension AVX cpuid-avx)"), cpu)
    negative("AVX512 forbidden", image, left, right,
             inventory.replace(
                 "(unavailable-extension AVX-512)",
                 "(admitted-extension AVX-512)"), cpu)
    negative("X86-64 missing", image, left, right,
             inventory.replace("(admitted-extension X86-64)", ""), cpu)
    negative("OS AVX state missing", image, left, right, inventory,
             cpu.replace("(avx-state-check xgetbv-required)", ""))
    negative("wrong CPU model", image, left, right, inventory,
             cpu.replace("(cpu intel-core-i5-6400)", "(cpu other)"))
    need(count == 29, "неповний набір негативів ISA")
    return count


def main() -> None:
    p = argparse.ArgumentParser(description="Pinned Skylake ISA та живий D12 ADD ELF")
    p.add_argument("--корінь", required=True, type=pathlib.Path)
    p.add_argument("--elf", required=True, type=pathlib.Path)
    p.add_argument("--лівий", required=True, type=int)
    p.add_argument("--правий", required=True, type=int)
    p.add_argument("--самотест", action="store_true")
    a = p.parse_args()
    root = a.корінь.resolve()
    inventory = (root / "external/sens/lib/machine/cpu/"
                 "intel-core-i5-6400-inventory.lisp").read_text(encoding="utf-8")
    cpu = (root / "external/sens/lib/machine/cpu/"
           "intel-core-i5-6400.lisp").read_text(encoding="utf-8")
    image = a.elf.read_bytes()
    check(image, a.лівий, a.правий, inventory, cpu)
    negative = negative_tests(image, a.лівий, a.правий, inventory, cpu) \
        if a.самотест else 0
    print("СКАЙЛЕЙК-ISA-ГАРАЗД real-ELF64=так PIE=так RX=так "
          f"D12-MOV-ADD-AND=так негативів={negative} "
          "AVX2=лише-після-CPUID-XGETBV повний-ISA-аудит=ні "
          "енергія=ENERGY_NOT_MEASURED")


if __name__ == "__main__":
    try:
        main()
    except (EIsa, ValueError, OSError, UnicodeError) as exc:
        print("СКАЙЛЕЙК-ISA-ВІДМОВА: " + str(exc), file=sys.stderr)
        sys.exit(2)

# Фізична форма: borrowed input .elf → Python-owned bytes; 15-byte
# пролог — лише X86-BASE instruction witness, а не T5M/D12 значення.
# pinned .lisp з CPU — тільки host ISA proof; D7 не інтерпретується.
# Усі буфери живуть до завершення цього процесу, жодних файлів не пишемо.
# 1) Чому не дизасемблюємо T5M lookup як код?
# 2) Чому тільки X86-BASE і не AVX512?
# 3) Що дає XGETBV після CPUID?
# 4) Чому immediates не є SENS семантикою?
# 5) Чому потрібен окремий незалежний SENS REPL для відповіді?
