#!/usr/bin/env python3
"""G5.65: незалежний pinned SENS-оракул для пакетного фізичного D3 файла.

Усі входи — справжні packed T5M .sens. Upstream CLI обчислює
кожен унікальний фізичний корінь окремо; FPC виконує ті самі форми
як один фізичний файл (1, 6 або 64 D2-корені).

Це тестова проєкція вузьких D1-відповідей, НЕ власні закони SENS,
не другий T5M-reader і не виконання українських назв функцій.
"""
import pathlib
import subprocess
import sys
import tempfile

EXPECTED_TEXT = {
    b"0\n": ("0",),
    b"1\n": ("1",),
    b"()\n": ("000",),
}
CHECKS = 0


def require(condition, message):
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(message)


def run(command, input_data=None):
    return subprocess.run(
        command, input=input_data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=90, check=False
    )


def pack(packer, folder, name, words):
    # Єдиний фізичний кодувальник: реальний FPC senst5m,
    # Python не обчислює T5M байти й не допускає D2.
    path = folder / (name + ".words")
    path.write_text(" ".join(words) + "\n", encoding="ascii")
    result = run([packer, "--пакувати-слова", str(path)])
    require(result.returncode == 0 and result.stderr == b"" and result.stdout,
            "FPC не зміг пакувати " + name + ": " +
            result.stderr.decode("utf-8", "replace"))
    return result.stdout


def upstream(oracle, folder, name, physical):
    # На вхід незалежного SENS передаємо ТОЧНО ці байти .sens.
    path = folder / (name + ".sens")
    path.write_bytes(physical)
    result = run([oracle, str(path)])
    require(result.returncode == 0 and result.stderr == b"",
            "pinned SENS відхилив " + name + ": " +
            result.stderr.decode("utf-8", "replace"))
    require(result.stdout in EXPECTED_TEXT,
            "несподіваний фізичний результат pinned SENS " + name +
            " / " + repr(result.stdout))
    return result.stdout


def verify_output(packer, folder, name, actual, transcripts):
    require(len(transcripts) > 0, name + ": відсутні upstream відповіді")
    # Тестова вузька таблиця D1: текст результату тільки після справжнього
    # upstream виконання. Вона не є registry, evaluator або D12+ coerce.
    expected_words = []
    for answer in transcripts:
        require(answer in EXPECTED_TEXT, name + ": недопустимий transcript")
        expected_words.extend(EXPECTED_TEXT[answer])
    expected = pack(packer, folder, name + "-очікуваний", expected_words)
    require(actual == expected, name + ": packed T5M не збігся байт-у-байт")


def expect_reject(executor, folder, name, physical, fragment):
    path = folder / (name + ".sens")
    path.write_bytes(physical)
    result = run([executor, "--завантажити-сенс", str(path)])
    require(result.returncode != 0, name + ": не було відмови")
    require(result.stdout == b"", name + ": витік часткового stdout")
    require(fragment.encode("utf-8") in result.stderr,
            name + ": втрачена українська адресна діагностика: " +
            result.stderr.decode("utf-8", "replace"))


def main():
    require(len(sys.argv) == 4,
            "аргументи: sensfizfayl senst5m pinned-sens")
    executor, packer, oracle = [
        str(pathlib.Path(x).resolve()) for x in sys.argv[1:]
    ]
    for executable in (executor, packer, oracle):
        require(pathlib.Path(executable).is_file(),
                "не знайдено виконавця: " + executable)

    with tempfile.TemporaryDirectory(prefix="sens-fizfayl-orakul-") as tmp:
        folder = pathlib.Path(tmp)
        forms = [
            ("д1-істина", ("1",)),
            ("д1-хиба", ("0",)),
            ("порожнє", ("000",)),
            ("цитата-істина", ("10", "001", "1", "01")),
            ("цитата-хиба", ("10", "001", "0", "01")),
        ]
        independent = {}
        for name, words in forms:
            physical = pack(packer, folder, name, words)
            independent[name] = upstream(oracle, folder, name, physical)
        # Захист від оракула, який лише echo-ить вхід, або зміни Contract12.
        require([independent[name] for name, _ in forms] ==
                [b"1\n", b"0\n", b"()\n", b"1\n", b"0\n"],
                "pinned Contract12 змінив підтверджені фізичні D1/D3")

        def verify_batch(name, selected):
            words, answers = [], []
            for form_name, form_words in selected:
                words.extend(form_words)
                answers.append(independent[form_name])
            packed_input = pack(packer, folder, name + "-вхід", words)
            source = folder / (name + ".sens")
            source.write_bytes(packed_input)
            result = run([executor, "--завантажити-сенс", str(source)])
            require(result.returncode == 0 and result.stderr == b"",
                    name + ": помилка реального FPC batch: " +
                    result.stderr.decode("utf-8", "replace"))
            verify_output(packer, folder, name, result.stdout, answers)
            return result.stdout, answers

        verify_batch("один-корінь", forms[:1])
        verify_batch("шість-коренів", forms + forms[:1])
        long_forms = [forms[i % len(forms)] for i in range(64)]
        packed_result, answers = verify_batch("шістдесят-чотири", long_forms)

        # Негативні контролі компаратора: ані підроблений текст upstream,
        # ані повний/частковий зайвий physical payload не можуть пройти.
        bad = [
            ("підміна-результату", packed_result, [b"0\n"] + answers[1:]),
            ("зайвий-транскрипт", packed_result, answers + [b"1\n"]),
            ("втрачений-транскрипт", packed_result, answers[:-1]),
            ("подвійний-транскрипт", packed_result, [b"1\n0\n"] + answers[1:]),
            ("не-d1-транскрипт", packed_result, [b"2\n"] + answers[1:]),
            ("зіпсована-т5м", packed_result + b"\x00", answers),
            ("обірвана-т5м", packed_result[:-1], answers),
        ]
        for i, (name, output, forged) in enumerate(bad, 1):
            try:
                verify_output(packer, folder, "негатив-" + str(i),
                              output, forged)
            except AssertionError:
                continue
            raise AssertionError("компаратор прийняв " + name)

        # Пізній збій 64-го кореня: жоден з перших 63 результатів
        # не може бути оприлюднений, навіть коли вони вже виконалися.
        malformed = ("10", "000", "000", "01")
        valid63 = [forms[i % len(forms)] for i in range(63)]
        prefix = [w for _, words in valid63 for w in words]
        expect_reject(
            executor, folder, "помилка-на-64",
            pack(packer, folder, "пізня-форма", prefix + list(malformed)),
            "форма=64"
        )
        expect_reject(
            executor, folder, "65-коренів",
            pack(packer, folder, "65-форм", ["1"] * 65),
            "1..64"
        )
        expect_reject(
            executor, folder, "недопустимий-т5м",
            bytes([243]), "фізичний T5M"
        )
        verify_batch("після-відмови", [forms[3], forms[2], forms[1]])

    print("ФІЗИЧНИЙ-ФАЙЛ-ОРАКУЛ-ГАРАЗД "
          "upstream-окремих=5 FPC-пакетів=4 межа=64 "
          "пізня-відмова=форма64 stdout=атомарний "
          "негативів-компаратора=7 перевірок=" + str(CHECKS))
    print("МЕЖА: Core4=не-доведено REPL=не-повний "
          "D7=дані D12+=без-тлумачення")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as err:
        print("ФІЗИЧНИЙ-ФАЙЛ-ОРАКУЛ-ПРОВАЛ: " + str(err), file=sys.stderr)
        sys.exit(1)
