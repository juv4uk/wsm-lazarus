#!/usr/bin/env python3
"""G6.151: незалежний host-доказ виконання ELF64, не оракул мовних законів SENS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import stat
import struct
import subprocess
import sys
import tempfile
import time

MAX_ELF = 1024 * 1024
MAX_SENS = 65536
MAX_OUTPUT = 65536


class EvidenceError(Exception):
    pass


def demand(condition, explanation):
    if not condition:
        raise EvidenceError(explanation)


def get_bytes(path, suffix, maximum, executable=False):
    """Відкрити тільки звичайний файл без symlink; повернути owned bytes + FD."""
    demand(path.suffix == suffix, "невірне фізичне розширення файлу")
    # FIFO не повинен блокувати open() до перевірки fstat/S_ISREG.
    # O_NONBLOCK не змінює звичайне читання regular file.
    flags = (os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) |
             getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0))
    fd = os.open(path, flags)
    try:
        before = os.fstat(fd)
        demand(stat.S_ISREG(before.st_mode), "потрібен звичайний фізичний файл")
        demand(0 < before.st_size <= maximum, "перевищено фізичну квоту")
        if executable:
            demand(bool(before.st_mode & 0o111), "ELF не має права виконання")
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, min(8192, maximum - total + 1))
            if not chunk:
                break
            total += len(chunk)
            demand(total <= maximum, "файл виріс за фізичну квоту")
            chunks.append(chunk)
        after = os.fstat(fd)
        demand((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
               == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns),
               "фізичний файл змінено під час читання")
        return b"".join(chunks), fd
    except BaseException:
        os.close(fd)
        raise


def verify_elf(image):
    """Незалежний host ELF admission: один RX PT_LOAD, без loader/sections."""
    def le(offset, size):
        return int.from_bytes(image[offset:offset + size], "little")

    demand(120 < len(image) <= MAX_ELF, "хибна довжина ELF64")
    demand(image[:4] == b"\x7fELF" and image[4:7] == b"\x02\x01\x01"
           and image[7:16] == bytes(9), "хибна ідентичність ELF64")
    kind = le(16, 2)
    demand(kind in (2, 3) and le(18, 2) == 62 and le(20, 4) == 1,
           "потрібен Linux x86-64 ELF")
    base = 0x400000 if kind == 2 else 0
    demand(le(24, 8) == base + 120, "хибний машинний entry")
    demand(le(32, 8) == 64 and le(40, 8) == 0 and le(48, 4) == 0,
           "неприпустима структура ELF")
    demand(tuple(le(i, 2) for i in (52, 54, 56, 58, 60, 62))
           == (64, 56, 1, 0, 0, 0), "неприпустимі host-заголовки")
    demand(le(64, 4) == 1 and le(68, 4) == 5, "PT_LOAD мусить бути RX, не RWX")
    demand(le(72, 8) == 0 and le(80, 8) == base and le(88, 8) == base,
           "невірна адреса машинного сегмента")
    demand(le(96, 8) == len(image) and le(104, 8) == len(image)
           and le(112, 8) == 4096, "хибна геометрія PT_LOAD")
    return kind


def restricted_child(seconds):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT, MAX_OUTPUT))
    limit = max(2, int(seconds) + 1)
    resource.setrlimit(resource.RLIMIT_CPU, (limit, limit))


def execute_exact(fd, expected, seconds):
    """Виконати саме вже відкритий inode, не шлях, без shell і без GUI."""
    with tempfile.TemporaryDirectory(prefix="sens-native-proof-") as work:
        with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
            started = time.monotonic_ns()
            try:
                run = subprocess.run(
                    [f"/proc/self/fd/{fd}"], pass_fds=(fd,),
                    stdin=subprocess.DEVNULL, stdout=output, stderr=errors,
                    cwd=work, env={"PATH": "/usr/bin:/bin"},
                    timeout=seconds, check=False,
                    preexec_fn=lambda: restricted_child(seconds),
                )
            except subprocess.TimeoutExpired as exc:
                raise EvidenceError("тайм-аут виконуваного ELF64") from exc
            elapsed = time.monotonic_ns() - started
            output.seek(0)
            errors.seek(0)
            actual = output.read(MAX_OUTPUT + 1)
            stderr = errors.read(MAX_OUTPUT + 1)
    demand(run.returncode == 0, f"машинний ELF завершився з кодом {run.returncode}")
    demand(not stderr, "машинний ELF записав діагностику у stderr")
    demand(len(actual) <= MAX_OUTPUT, "машинна відповідь перевищує квоту")
    demand(actual == expected, "машинні байти не збігаються з фізичним .sens")
    return actual, elapsed


def sha(data):
    return hashlib.sha256(data).hexdigest()


def attest(source, executable, expected, report, seconds):
    demand(sys.platform == "linux" and os.uname().machine == "x86_64",
           "потрібен Linux x86-64")
    demand(0.05 <= seconds <= 30, "межа часу поза допустимим інтервалом")
    demand(not report.exists() and not report.is_symlink(),
           "звіт уже існує; перезапис заборонено")
    source_bytes, source_fd = get_bytes(source, ".sens", MAX_SENS)
    try:
        expected_bytes, expected_fd = get_bytes(expected, ".sens", MAX_SENS)
        try:
            elf_bytes, elf_fd = get_bytes(executable, ".elf", MAX_ELF, True)
            try:
                kind = verify_elf(elf_bytes)
                actual, elapsed = execute_exact(elf_fd, expected_bytes, seconds)
                os.lseek(elf_fd, 0, os.SEEK_SET)
                demand(os.read(elf_fd, len(elf_bytes) + 1) == elf_bytes,
                       "машинний inode змінено після виконання")
            finally:
                os.close(elf_fd)
        finally:
            os.close(expected_fd)
    finally:
        os.close(source_fd)
    proof = {
        "схема": "sens-native-elf-execution/1",
        "статус": "побайтово_виконано",
        "джерело_sha256": sha(source_bytes),
        "джерело_байтів": len(source_bytes),
        "elf_sha256": sha(elf_bytes),
        "elf_байтів": len(elf_bytes),
        "elf_host_тип": "ET_DYN" if kind == 3 else "ET_EXEC",
        "очікуване_sha256": sha(expected_bytes),
        "виконане_sha256": sha(actual),
        "відповідь_байтів": len(actual),
        "час_процесу_нс": elapsed,
        "обсяг_часу": "cold exec+machine+capture, НЕ швидкість мови",
        "семантичний_оракул": "НЕ_ПЕРЕВІРЕНО",
        "енергія": "ENERGY_NOT_MEASURED",
    }
    created = False
    try:
        outfd = os.open(report, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                        | getattr(os, "O_NOFOLLOW", 0), 0o600)
        created = True
        with os.fdopen(outfd, "w", encoding="utf-8") as out:
            json.dump(proof, out, ensure_ascii=False, sort_keys=True, indent=2)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
    except BaseException:
        if created:
            os.unlink(report)
        raise
    print(f"НАТИВНИЙ-ELF-ДОКАЗ: ELF64={kind} stdout={len(actual)} "
          "орaкул=НЕ_ПЕРЕВІРЕНО energy=NOT-MEASURED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--джерело", type=Path, required=True)
    parser.add_argument("--машина", type=Path, required=True)
    parser.add_argument("--очікувано", type=Path, required=True)
    parser.add_argument("--звіт", type=Path, required=True)
    parser.add_argument("--межа-секунд", type=float, default=3)
    a = parser.parse_args()
    try:
        attest(a.джерело, a.машина, a.очікувано, a.звіт, a.межа_секунд)
    except (EvidenceError, OSError, ValueError) as exc:
        print(f"НАТИВНИЙ-ELF-ВІДМОВА: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
