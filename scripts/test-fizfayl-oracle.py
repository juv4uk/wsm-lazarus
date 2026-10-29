#!/usr/bin/env python3
"""G5.64: фізичний багатокореневий FPC-файл проти незалежного pinned SENS.

Кожен D2-корінь подається незалежному SENS у ТИХ САМИХ T5M байтах;
жодного mint із .lisp чи англійського dispatch.
"""
from pathlib import Path
import subprocess
import sys
import tempfile


class ProofError(Exception):
    """Відмова інженерного доказу, а не значення мови SENS."""


def ensure(condition, message):
    if not condition:
        raise ProofError(message)


def run(args, *, timeout=45):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=False)


def pack(packer, directory, label, words):
    """Список exact бітових Wn слів → власні packed T5M байти."""
    source = directory / (label + ".words")
    source.write_text(" ".join(words) + "\n", encoding="ascii")
    result = run([packer, "--пакувати-слова", str(source)])
    ensure(result.returncode == 0 and result.stdout and not result.stderr,
           label + ": фізичний FPC T5M пакувальник відмовив")
    return result.stdout


def oracle_single(oracle, directory, label, physical):
    """Запозичений фізичний байтовий вхід; один незалежний SENS процес."""
    source = directory / (label + ".sens")
    source.write_bytes(physical)
    result = run([oracle, str(source)])
    ensure(result.returncode == 0 and not result.stderr,
           label + ": незалежний SENS відхилив точно ці .sens байти: " +
           result.stderr.decode("utf-8", errors="replace"))
    return result.stdout


# Тільки три перевірені контрактні result-координати.
# Це ТЕСТОВИЙ компаратор, НЕ виконавець і НЕ бібліотека Pascal.
# Питання: чому D3:000 не є D1:0? Чому D12 не допущений?
# Чому не можна порівняти лише перший рядок SENS stdout?
# Чому output packer не визначає семантику виконання?
def transcript_word(transcript):
    lookup = {b"0\n": "0", b"1\n": "1", b"()\n": "000"}
    ensure(transcript in lookup,
           "непідтверджена/додаткова відповідь upstream SENS")
    return lookup[transcript]


def verify_physical_reply(actual, expected, count):
    """Два власні T5M буфери після виконання; рівність усіх байтів."""
    ensure(actual == expected and len(actual) > 0,
           "незалежний семантичний SENS != повна FPC T5M-відповідь "
           "коренів=" + str(count))


def main():
    ensure(len(sys.argv) == 4,
           "параметри: sensfizfayl senst5m pinned-sens")
    evaluator, packer, oracle = [str(Path(item).resolve())
                                for item in sys.argv[1:]]
    for path in [evaluator, packer, oracle]:
        ensure(Path(path).is_file(), "відсутній виконуваний файл: " + path)

    # Синтаксично перевірені тестові D2-корені, НЕ нові закони SENS.
    corpus = [
        ("один", ("1",)),
        ("нуль", ("0",)),
        ("порожній", ("000",)),
        ("цитата-так", ("10", "001", "1", "01")),
        ("цитата-ні", ("10", "001", "0", "01")),
    ]
    count = 0
    with tempfile.TemporaryDirectory(prefix="sens-fizfayl-orakul-") as root:
        directory = Path(root)
        verified = {}
        for name, words in corpus:
            physical = pack(packer, directory, name, words)
            transcript = oracle_single(oracle, directory, name, physical)
            verified[name] = (words, transcript_word(transcript))
        ensure({name: value[1] for name, value in verified.items()} ==
               {"один": "1", "нуль": "0", "порожній": "000",
                "цитата-так": "1", "цитата-ні": "0"},
               "upstream Contract12: змінено точні фізичні свідки")

        for label, names in [
            ("один-корінь", ["цитата-так"]),
            ("три-корені", ["один", "цитата-ні", "порожній"]),
            ("шістдесят-чотири", [corpus[i % len(corpus)][0]
                                 for i in range(64)]),
        ]:
            input_words = [part for name in names
                           for part in verified[name][0]]
            # Справді виконуємо КОЖЕН із 68 коренів незалежним SENS,
            # а не використовуємо 5 попередньо кешованих відповідей.
            result_words = []
            for position, name in enumerate(names, 1):
                root_label = label + "-корінь-" + str(position)
                root_bytes = pack(packer, directory, root_label,
                                  verified[name][0])
                transcript = oracle_single(oracle, directory, root_label,
                                           root_bytes)
                exact_word = transcript_word(transcript)
                ensure(exact_word == verified[name][1],
                       "розходження upstream у повторному корені " +
                       root_label)
                result_words.append(exact_word)
            # T5M пакується поверх ПОСЛІДОВНОСТІ exact слів, а не
            # конкатенацією байтових T5M файлів із padding.
            source_bytes = pack(packer, directory, label + "-вхід", input_words)
            expected_bytes = pack(packer, directory, label + "-вихід",
                                  result_words)
            path = directory / (label + ".sens")
            path.write_bytes(source_bytes)
            actual = run([evaluator, "--завантажити-сенс", str(path)])
            ensure(actual.returncode == 0 and not actual.stderr,
                   label + ": FPC не виконав файл: " +
                   actual.stderr.decode("utf-8", errors="replace"))
            verify_physical_reply(actual.stdout, expected_bytes, len(names))
            count += len(names)

            # Негативні мутації тестового компаратора.
            # Не можна приймати чужі байти, тільки префікс або
            # правильні слова з додатковим T5M коренем.
            corrupted = bytes([actual.stdout[0] ^ 1]) + actual.stdout[1:]
            for false_output in (corrupted, actual.stdout[:-1],
                                 actual.stdout + b"\x00", b""):
                try:
                    verify_physical_reply(false_output, expected_bytes,
                                          len(names))
                except ProofError:
                    pass
                else:
                    raise ProofError(label + ": компаратор допустив підміну")

        # Попередні вже виконані відповіді НЕ публікувати, коли
        # останній D2-корінь неприпустимий (semantic failure).
        late = pack(packer, directory, "пізня-помилка",
                    ["1", "0", "10", "000", "000", "01"])
        malformed = pack(packer, directory, "неповний-D2",
                         ["1", "10", "001", "1"])
        cases = [
            ("пізня-семантична-помилка", late, "форма=3"),
            ("обірваний-D2", malformed, "D2:"),
            ("пошкоджений-T5M", pack(packer, directory, "валідний", ["1"]) +
             b"\xf3", "фізичний T5M"),
        ]
        for name, physical, diagnostic in cases:
            path = directory / (name + ".sens")
            path.write_bytes(physical)
            result = run([evaluator, "--завантажити-сенс", str(path)])
            ensure(result.returncode != 0 and result.stdout == b"" and
                   diagnostic.encode("utf-8") in result.stderr,
                   name + ": відмова дала частковий stdout або втратила "
                   "адресну діагностику")
        ensure(count == 68, "не перевірені всі 1+3+64 фізичні корені")

        # Виконавець залишається придатним після попередніх відмов.
        again = directory / "після-помилки.sens"
        again.write_bytes(pack(packer, directory, "відновлення", ["0"]))
        actual = run([evaluator, "--завантажити-сенс", str(again)])
        ensure(actual.returncode == 0 and not actual.stderr and
               actual.stdout == pack(packer, directory, "очікуваний-нуль", ["0"]),
               "неможливе відновлення після фізичної відмови")

    print("ФАЙЛОВИЙ-SENS-ОРАКУЛ-ГАРАЗД коренів=68 пакети=1/3/64 "
          "незалежний-SENS=так байти-T5M=точні негативів=15 "
          "пізня-відмова=без-stdout відновлення=так")
    print("МЕЖА: D1/D3 тільки; Core4=не-доведено REPL=не-повний "
          "D7=лише-дані D12+=без-перетлумачення")


if __name__ == "__main__":
    try:
        main()
    except (ProofError, OSError, subprocess.TimeoutExpired) as error:
        print("ФАЙЛОВИЙ-SENS-ОРАКУЛ-ПРОВАЛ: " + str(error), file=sys.stderr)
        sys.exit(1)
