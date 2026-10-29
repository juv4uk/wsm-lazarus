#!/usr/bin/env python3
"""G3.48: механічний доказ збереження точних фізичних слів у першому Core1."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"


def need(value, message):
    if not value:
        raise AssertionError(message)


def pack(words):
    """Лише тестовий T5M-кодувальник; НЕ реалізація закону SENS."""
    trits = []
    for index, word in enumerate(words):
        need(bool(word) and set(word) <= {"0", "1"}, "некоректне двійкове слово тесту")
        if index:
            trits.append(2)
        trits.extend(int(bit) for bit in word)
    while len(trits) % 5:
        trits.append(2)
    return bytes(
        sum(trits[i + j] * 3 ** (4 - j) for j in range(5))
        for i in range(0, len(trits), 5)
    )


def selfcheck():
    need(pack(["0"]) != pack(["00"]), "пакувальник стер фізичну ширину")
    need(pack(["0000001"]) != pack(["000000000001"]), "D7/D12 змішалися")
    need(pack(["0", "1"]) != pack(["01"]), "втрачена межа фізичних слів")
    need(all(b < 243 for b in pack(["10", "1110", "1", "0" * 191 + "1", "0", "01"])),
         "T5M байти поза фізичним алфавітом")
    print("CORE1-ШИРИНИ-САМОПЕРЕВІРКА-ГАРАЗД")


def invoke(executable, argument_path):
    return subprocess.run(
        [str(executable), "--виконати-перший", str(ROOT), str(argument_path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=False
    )


def no_leak(proc, label):
    # heaptrc може нічого не друкувати, коли витоків немає.
    # Якщо друкує підсумок — жоден ненульовий залишок не допускається.
    lines = proc.stderr.splitlines()
    leftovers = [line for line in lines if b"unfreed memory blocks" in line]
    need(not leftovers or all(b"0 unfreed memory blocks" in line for line in leftovers),
         label + ": підтверджений витік heaptrc: " + repr(proc.stderr[-500:]))


def run():
    selfcheck()
    need(shutil.which(os.environ.get("FPC", "fpc")), "бракує реального FPC")
    subprocess.run([str(ROOT / "scripts/check-pin.sh")], cwd=ROOT, check=True, timeout=90)
    actual = subprocess.check_output(
        ["git", "-C", str(ROOT / "external/sens"), "rev-parse", "HEAD"],
        timeout=15, text=True
    ).strip()
    need(actual == PIN, "Core1 взято не з pinned SENS")
    need((ROOT / "external/sens/lib/core1.sens").is_file(), "бракує фізичного Core1")

    with tempfile.TemporaryDirectory(prefix="core1-shyryny-") as dirname:
        tmp = Path(dirname)
        (tmp / "units").mkdir()
        (tmp / "bin").mkdir()
        executable = tmp / "bin/senscore1vykon"
        compiler = os.environ.get("FPC", "fpc")
        command = [
            compiler, "-B", "-Mobjfpc", "-Cr", "-Co", "-Ci", "-gl", "-gh",
            "-Fu" + str(ROOT / "src"), "-FU" + str(tmp / "units"),
            "-FE" + str(tmp / "bin"), "-osenscore1vykon",
            str(ROOT / "src/senscore1vykon.lpr")
        ]
        compiled = subprocess.run(
            command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=180, check=False
        )
        need(compiled.returncode == 0 and executable.is_file(),
             "не вдалася справжня FPC-збірка: " +
             compiled.stdout.decode("utf-8", errors="replace")[-4000:])

        positives = 0
        # Однаковий молодший біт не дозволяє звужувати D7 до D12+ і навпаки.
        for width in (7, 12, 24, 48, 96, 192):
            for bits in ("0" * (width - 1) + "1", "1" + "0" * (width - 1)):
                argument = tmp / ("w" + str(width) + "-" + str(positives) + ".sens")
                argument.write_bytes(pack(["10", "1110", "1", bits, "0", "01"]))
                proc = invoke(executable, argument)
                need(proc.returncode == 0,
                     "W" + str(width) + ": FPC відмовив: " + repr(proc.stderr[-1000:]))
                need(proc.stdout == pack([bits]),
                     "W" + str(width) + ": втрачено ширину/провідні нулі/біти")
                no_leak(proc, "W" + str(width))
                positives += 1

        rejected = 0

        def reject(name, content, extension=".sens", exitcode=2):
            nonlocal rejected
            argument = tmp / (name + extension)
            argument.write_bytes(content)
            proc = invoke(executable, argument)
            need(proc.returncode == exitcode,
                 name + ": неправильний код виходу " + str(proc.returncode) +
                 " " + repr(proc.stderr[-500:]))
            need(proc.stdout == b"", name + ": часткове фізичне stdout")
            need(b"CORE1-" in proc.stderr, name + ": немає пояснення відмови")
            if exitcode == 2:
                no_leak(proc, name)
            rejected += 1

        valid = ["10", "1110", "1", "000000000001", "0", "01"]
        reject("текстова-підміна", pack(valid), extension=".lisp", exitcode=64)
        reject("пошкоджений-t5m", bytes([243]))
        reject("обірваний-d2", pack(valid[:-1]))
        reject("немає-другого", pack(["10", "1110", "1", "01"]))
        reject("хибний-конструктор", pack(["10", "1001", "1", "0", "01"]))
        reject("зайвий-корінь", pack(valid + ["1"]))
        # Після серії відмов ніяка глобальна таблиця ширин не повинна змінитись.
        argument = tmp / "відновлення.sens"
        atom = "0" * 191 + "1"
        argument.write_bytes(pack(["10", "1110", "1", atom, "0", "01"]))
        restored = invoke(executable, argument)
        need(restored.returncode == 0 and restored.stdout == pack([atom]),
             "після відмов W192 більше не зберігається")
        no_leak(restored, "відновлення")
        print("CORE1-ШИРИНИ-ГАРАЗД FPC=так pinned=" + PIN +
              " фізичних=" + str(positives + 1) + " негативів=" +
              str(rejected) + " D7=дані D12+=opaque арифметика=ні")


if __name__ == "__main__":
    if sys.argv[1:] == ["--самоперевірка"]:
        selfcheck()
    elif len(sys.argv) == 1:
        run()
    else:
        sys.exit("Використання: test-core1-tochni-shyryny.py [--самоперевірка]")
