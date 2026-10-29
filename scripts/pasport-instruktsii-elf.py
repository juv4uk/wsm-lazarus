#!/usr/bin/env python3
"""Механічний паспорт машинних інструкцій ELF, не тлумач SENS і не джоулі.

Вхід: borrowed bytes уже згенерованого .elf. Вихід: новий JSON без перезапису.
Обсяг пам'яті: до 1 МіБ образу плюс тимчасовий дизасемблерний файл;
тимчасовий каталог видаляється, а звіт публікується лише після повного успіху.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

MAX_ELF = 1024 * 1024
HEADER_BYTES = 120
IDENT = b"\x7fELF\x02\x01\x01" + b"\x00" * 9
INSTRUCTION = re.compile(r"^\s*([0-9a-fA-F]+):\s*((?:[0-9a-fA-F]{2}[ \t]+)+)(.*)$")
BAD_MNEMONICS = {"(bad)", ".byte", "data16", "addr32", "rex", "rex.w", "cs", "ds", "es", "ss", "fs", "gs"}


def require(ok: bool, cause: str) -> None:
    if not ok:
        raise ValueError(cause)


def split_machine_and_data(image: bytes) -> tuple[bytes, bytes]:
    """Відомий фізичний RIP-літерал після 33 байтів коду, без SENS тлумачення.

    Цей один layout перевіряється побайтно. Незнайомий layout не
    відгадується: повне x86-декодування в іншому разі відмовить.
    """
    body = image[HEADER_BYTES:]
    fixed_start = bytes.fromhex("b8 01 00 00 00 bf 01 00 00 00 48 8d 35")
    fixed_tail = bytes.fromhex("0f 05 b8 3c 00 00 00 31 ff 0f 05")
    if body.startswith(fixed_start):
        require(len(body) >= 34, "неповний RIP-літерал")
        require(body[17:18] == b"\\xba" and body[22:33] == fixed_tail,
                "непідтверджена межа машинного шаблону й даних")
        displacement = struct.unpack_from("<i", body, 13)[0]
        literal_size = struct.unpack_from("<I", body, 18)[0]
        require(displacement == 16 and literal_size == len(body) - 33,
                "RIP-адреса чи довжина машинного T5M літерала не збігається")
        return body[:33], body[33:]
    return body, b""


def verify_elf(data: bytes) -> tuple[str, bytes, bytes]:
    """Тільки фізичний RX ELF64-профіль з wsm.elfgeometry, без SENS закону."""
    require(HEADER_BYTES < len(data) <= MAX_ELF, "неприпустима довжина ELF")
    fields = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    ident, kind, machine, version, entry, phoff, shoff, flags, ehsize, phentsize, phnum, shentsize, shnum, shstr = fields
    require(ident == IDENT, "неправильний ELF64 заголовок")
    require(kind in (2, 3) and machine == 62 and version == 1,
            "неприпустима машина або тип ELF")
    require((phoff, shoff, flags, ehsize, phentsize, phnum, shentsize, shnum, shstr) ==
            (64, 0, 0, 64, 56, 1, 0, 0, 0),
            "неприпустима геометрія таблиць ELF")
    base = 0 if kind == 3 else 0x400000
    segment = struct.unpack_from("<IIQQQQQQ", data, 64)
    require(segment == (1, 5, 0, base, base, len(data), len(data), 4096),
            "очікується тільки один RX PT_LOAD із цілим образом")
    require(entry == base + HEADER_BYTES, "точка входу не збігається з машинним кодом")
    return ("PIE" if kind == 3 else "EXEC"), *split_machine_and_data(data)


def disassemble(code: bytes) -> dict[str, int]:
    """Підрахунок GNU objdump, з повним фізичним покриттям усіх байтів."""
    with tempfile.TemporaryDirectory(prefix="sens-instr-") as temporary:
        path = Path(temporary) / "машина.bin"
        path.write_bytes(code)
        result = subprocess.run(
            ["objdump", "-D", "-b", "binary", "-m", "i386:x86-64",
             "-M", "intel", "--insn-width=16", str(path)],
            capture_output=True, text=True, timeout=15, check=False,
        )
    require(result.returncode == 0, "GNU objdump відхилив машинний код")
    counts: dict[str, int] = {}
    offset = 0
    for line in result.stdout.splitlines():
        match = INSTRUCTION.match(line)
        if not match:
            continue
        instruction_offset = int(match.group(1), 16)
        raw = bytes.fromhex(match.group(2))
        mnemonic = match.group(3).strip().split()
        require(instruction_offset == offset and len(raw) > 0,
                "дизасемблер пропустив або переставив байти")
        require(bool(mnemonic) and mnemonic[0].lower() not in BAD_MNEMONICS
                and re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_.]*", mnemonic[0]) is not None,
                "неповна або невідома машинна інструкція")
        name = mnemonic[0].lower()
        counts[name] = counts.get(name, 0) + 1
        offset += len(raw)
    require(offset == len(code) and bool(counts),
            "не всі фізичні байти розібрані як інструкції")
    return dict(sorted(counts.items()))


def publish_new(path: Path, body: bytes) -> None:
    """Окремий inode 0600, atomic hardlink EEXIST, навіть для dangling symlink."""
    require(path.suffix == ".json" and path.parent.is_dir(),
            "потрібен новий файл .json в існуючому каталозі")
    descriptor, temporary = tempfile.mkstemp(prefix=".sens-instr-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(body)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
    finally:
        os.unlink(temporary)


def main(args: list[str]) -> int:
    if len(args) != 2:
        print("Виклик: pasport-instruktsii-elf.py вхід.elf новий-звіт.json",
              file=sys.stderr)
        return 64
    source, output = map(Path, args)
    try:
        require(source.suffix == ".elf", "вхід має бути .elf, а не .sens/.lisp")
        image = source.read_bytes()
        kind, machine, inline_data = verify_elf(image)
        opcodes = disassemble(machine)
        report = {
            "формат": "ELF64-x86-64",
            "тип": kind,
            "байтів_elf": len(image),
            "байтів_машини": len(machine),
            "байтів_даних": len(inline_data),
            "інструкцій": sum(opcodes.values()),
            "мнемоніки": opcodes,
            "sha256_elf": hashlib.sha256(image).hexdigest(),
            "sha256_машини": hashlib.sha256(machine).hexdigest(),
            "sha256_даних": hashlib.sha256(inline_data).hexdigest(),
            "енергія": "НЕ_ВИМІРЯНО",
            "оракул_SENS": "НЕ_ПЕРЕВІРЕНО",
        }
        document = (json.dumps(report, ensure_ascii=False, sort_keys=True,
                               separators=(",", ":")) + "\n").encode("utf-8")
        publish_new(output, document)
        print("ІНСТРУКЦІЇ-ELF-ГАРАЗД: інструкцій=" + str(report["інструкцій"]) +
              " машинних-байтів=" + str(len(machine)) +
              " енергія=НЕ_ВИМІРЯНО")
        return 0
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print("ІНСТРУКЦІЇ-ELF-ВІДМОВА: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

# Питання: (1) Чому RX-геометрія не доводить значення SENS?
# (2) Чому дизасемблювання кожного байта сильніше за простий grep opcode?
# (3) Чому кількість інструкцій не дорівнює витраченій енергії?
# (4) Чому os.link захищає існуючу ціль і висяче символьне посилання?
# (5) Кому належать bytes, тимчасовий inode та фінальний JSON?
