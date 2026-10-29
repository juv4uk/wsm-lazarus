#!/usr/bin/env python3
"""G4.49: незалежна фізична диференційна перевірка D4:1001, pinned SENS 12.

SENS — єдиний семантичний оракул. Цей скрипт НЕ є T5M codec,
reader, evaluator, таблицею законів чи .lisp проєкцією.
Кожне фізичне слово кодує ВЖЕ злитий FPC senst5m.
"""
import pathlib
import subprocess
import sys
import tempfile

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
SEEN = 0


def require(condition, reason):
    global SEEN
    SEEN += 1
    if not condition:
        raise AssertionError(reason)


def run(command, **kwargs):
    return subprocess.run(
        [str(x) for x in command],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=100, check=False, **kwargs
    )


def make_physical(packer, directory, label, words):
    """Тільки наявний FPC T5M: exact words -> canonical packed bytes."""
    require(bool(words) and all(w and set(w) <= {"0", "1"} for w in words),
            label + ": зіпсовано тестові двійкові слова")
    view = directory / (label + ".words")
    view.write_bytes((" ".join(words) + "\n").encode("ascii"))
    encoded = run([packer, "--пакувати-слова", view])
    require(encoded.returncode == 0 and encoded.stdout and not encoded.stderr,
            label + ": FPC T5M packer: " +
            encoded.stderr.decode("utf-8", "replace"))
    physical = directory / (label + ".sens")
    physical.write_bytes(encoded.stdout)
    decoded = run([packer, "--перегляд", physical])
    require(decoded.returncode == 0 and decoded.stdout == view.read_bytes(),
            label + ": порушено точний T5M round-trip")
    return physical


def selector_words(values):
    """D4 координати з pinned d4.lisp, це ТЕСТОВА форма, не реалізація закону."""
    return ["10", "1001", "10", "1110", *values, "01", "01"]


def fixture(i):
    """Відтворюване сімейство різної довжини/наповнення/порожнечі."""
    length = 2 + (i % 9)
    state = (i + 1) * 2654435761 & 0xFFFFFFFF
    values = []
    for index in range(length):
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        values.append(("0", "1", "000")[(state >> 19) % 3])
    # Окремі свідки D1:0, D1:1 та D3:000 — ніколи не ототожнювати.
    if i < 3:
        values[1] = ("0", "1", "000")[i]
    return values


def independent_oracle(oracle, physical, label):
    result = run([oracle, physical])
    require(result.returncode == 0 and result.stderr == b"",
            label + ": незалежний SENS відхилив форму: " +
            result.stderr.decode("utf-8", "replace"))
    from_pinned = {b"0\n": "0", b"1\n": "1", b"()\n": "000"}
    require(result.stdout in from_pinned,
            label + ": несподіваний SENS transcript " + repr(result.stdout))
    return from_pinned[result.stdout]


def execute(executor, root, source, result_path, batch):
    return run([executor, "--пакет" if batch else "--виконати",
                root, source, result_path])


def expect_rejection(executor, root, folder, label, words, batch=True,
                     physical_suffix=b"", expected_code=2):
    source = make_physical(folder["packer"], folder["path"], label, words)
    if physical_suffix:
        source.write_bytes(source.read_bytes() + physical_suffix)
    target = folder["path"] / (label + "-result.sens")
    response = execute(executor, root, source, target, batch)
    require(response.returncode == expected_code,
            label + ": неправильний код відмови " +
            str(response.returncode) + ": " +
            response.stderr.decode("utf-8", "replace"))
    require(response.stdout == b"", label + ": витік часткового stdout")
    require(not target.exists(), label + ": опубліковано часткову відповідь")
    require(bool(response.stderr), label + ": втрачено діагностику")


def main():
    require(len(sys.argv) == 5,
            "використання: test-core4-d4-orakul.py ROOT CORE4_CLI T5M_CLI SENS_CLI")
    root, executor, packer, oracle = [str(pathlib.Path(s).resolve())
                                     for s in sys.argv[1:]]
    for binary in (executor, packer, oracle):
        require(pathlib.Path(binary).is_file(), "відсутній виконавець " + binary)

    with tempfile.TemporaryDirectory(prefix="sens-d4-orakul-") as tmp:
        folder = pathlib.Path(tmp)
        calls = [selector_words(fixture(i)) for i in range(64)]
        answers = []
        for i, words in enumerate(calls):
            label = "виклик-" + str(i + 1)
            physical = make_physical(packer, folder, label, words)
            answers.append(independent_oracle(oracle, physical, label))
        require(answers[0:3] == ["0", "1", "000"],
                "незалежний SENS не розрізнив D1:0, D1:1, D3:000")

        # FPC --пакет виконує весь список у тому самому TCore4Runtime.
        # Немає конкатенації padded T5M файлів: усі слова пакує senst5m.
        for size in (1, 4, 64):
            combined = [word for form in calls[:size] for word in form]
            source = make_physical(packer, folder, "пакет-" + str(size), combined)
            expected = make_physical(packer, folder, "еталон-" + str(size),
                                     answers[:size])
            target = folder / ("пакет-" + str(size) + "-result.sens")
            response = execute(executor, root, source, target, batch=True)
            require(response.returncode == 0 and target.is_file(),
                    "FPC пакет " + str(size) + ": " +
                    response.stderr.decode("utf-8", "replace"))
            require(target.read_bytes() == expected.read_bytes(),
                    "FPC пакет " + str(size) +
                    ": реальні canonical T5M байти не збіглися з pinned SENS")
            require(("форм=" + str(size)).encode("utf-8") in response.stdout,
                    "пакет утратив перевірений лічильник фізичних форм")

        # Окремий виконуваний виклик того самого фізичного D4:1001.
        source = folder / "виклик-1.sens"
        target = folder / "один-result.sens"
        response = execute(executor, root, source, target, batch=False)
        require(response.returncode == 0 and target.is_file(),
                "Core4 --виконати не виконав перший точний D4")
        expected = make_physical(packer, folder, "очікуваний-один",
                                 [answers[0]])
        require(target.read_bytes() == expected.read_bytes(),
                "пакет та один виклик дали різні фізичні результати")

        state = {"packer": packer, "path": folder}
        # 64-та форма некоректна ПІСЛЯ 63 виконуваних форм.
        broken_last = ["10", "1001", "10", "1110", "1", "01", "01"]
        expect_rejection(executor, root, state, "пізня-помилка-64",
                         [w for form in calls[:63] for w in form] + broken_last)
        expect_rejection(executor, root, state, "зайва-65-та-форма",
                         [w for form in calls for w in form] + calls[0])
        expect_rejection(executor, root, state, "пошкоджений-T5M",
                         calls[0], physical_suffix=bytes([243]))
        expect_rejection(executor, root, state, "неправильна-арність",
                         broken_last, batch=False)

        # Приватний no-clobber: зайнятий файл має зберегти ВСІ байти.
        occupied = folder / "не-перезаписувати.sens"
        occupied.write_bytes(b"foreign-content")
        response = execute(executor, root, source, occupied, batch=False)
        require(response.returncode == 2 and occupied.read_bytes() ==
                b"foreign-content", "перезаписано наявний результат")

        # Recovery в тому самому наборі позитивних/негативних артефактів.
        after = folder / "після-відмов.sens"
        response = execute(executor, root, source, after, batch=False)
        require(response.returncode == 0 and
                after.read_bytes() == expected.read_bytes(),
                "після негативів втрачено фізичний результат")
        print("CORE4-Д4-ОРАКУЛ-ГАРАЗД",
              "SENS-викликів=64",
              "FPC-пакети=1,4,64",
              "одиночний=так",
              "D1/D3=точні",
              "негативи=5",
              "перевірок=" + str(SEEN),
              "Core4=частковий")


if __name__ == "__main__":
    main()
