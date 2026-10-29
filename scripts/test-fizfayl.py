#!/usr/bin/env python3
"""G5.63: фізичний багатокореневий файл -> виконані точні T5M байти."""
import pathlib
import subprocess
import sys
import tempfile

executable, packer = sys.argv[1:3]
checks = 0

def need(condition, description):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(description)

with tempfile.TemporaryDirectory(prefix="sens-fizfayl-") as temp:
    directory = pathlib.Path(temp)

    def packed(words):
        source = directory / "test.words"
        source.write_text(words + "\n", encoding="utf-8")
        result = subprocess.run(
            [packer, "--пакувати-слова", str(source)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        need(result.returncode == 0 and result.stdout,
             "FPC T5M пакувальник: " + result.stderr.decode(errors="replace"))
        return result.stdout

    def invoke(content, extension=".sens", mode="--завантажити-сенс"):
        source = directory / ("програма" + extension)
        source.write_bytes(content)
        return subprocess.run(
            [executable, mode, str(source)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )

    def success(source_words, expected_words, label):
        result = invoke(packed(source_words))
        want = packed(expected_words)
        need(result.returncode == 0, label + ": " +
             result.stderr.decode(errors="replace"))
        need(result.stderr == b"", label + ": неочікувана діагностика")
        need(result.stdout == want, label + ": порушено фізичний T5M")

    def refused(content, label, diagnostic=None, extension=".sens",
                mode="--завантажити-сенс", exit_code=2):
        result = invoke(content, extension=extension, mode=mode)
        need(result.returncode == exit_code, label + ": неправильний exit")
        need(result.stdout == b"", label + ": частковий stdout")
        if diagnostic:
            need(diagnostic.encode("utf-8") in result.stderr,
                 label + ": відсутня адресна діагностика " +
                 result.stderr.decode(errors="replace"))

    # Кожен обчислений результат є фізичним словом/коренем, не decimal.
    success("1", "1", "один канонічний D1")
    success("1 10 001 1 01 0", "1 1 0",
            "три корені: D1, виконана D3:001 цитата, D1")
    success("10 111 1 000 01 1", "10 1 01 1",
            "складена відповідь D3:111 разом із D1")
    success(" ".join(["1", "0"] * 32), " ".join(["1", "0"] * 32),
            "64 окремі D2-корені з одним виконавцем")

    # Неприпустима остання форма НЕ дозволяє опублікувати ранні відповіді.
    refused(packed("1 0 10 000 000 01"), "пізня помилкова D3-голова",
            "форма=3 слово=3")
    refused(packed("1 10 001 1"), "обірваний останній D2-корінь",
            "D2:")
    refused(packed(" ".join(["1"] * 65)), "65 коренів", "1..64")
    refused(bytes([243]), "зіпсований T5M", "фізичний T5M")
    refused(b"", "нуль байтів", "1..65536")
    refused(b"\x00" * 65537, "перевищено ліміт файла", "1..65536")
    refused(b"(1)\n", "текст не є канонічним фізичним .sens",
            "фізичний T5M")
    refused(packed("1"), "заборонено .lisp як вхід",
            extension=".lisp", exit_code=64)
    refused(packed("1"), "непідтверджений режим CLI",
            mode="--виконати", exit_code=64)
    success("10 001 0 01 1", "0 1",
            "новий файл успішний після попередніх відмов")

print("ФІЗИЧНИЙ-ФАЙЛ-ГАРАЗД: 1/3/64 коренів, D3:001/D3:111, "
      "паковані T5M точні, пізня відмова без stdout, "
      "D2/EOF/T5M/режим/ліміти, перевірок=" + str(checks))
print("ФІЗИЧНИЙ-ФАЙЛ-МЕЖА: Core4=ні REPL=ні D12+=не-тлумачиться")
