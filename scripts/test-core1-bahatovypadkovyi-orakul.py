#!/usr/bin/env python3
"""G3.47: диференційний реальний Core1, а не ізольований D4:1001.

FPC виконує pinned фізичний core1.sens через наявний senscore1vykon.
Незалежний SENS завантажує справжній pinned core1.lisp і ВИКЛИКАЄ
його перше бібліотечне визначення. Людська «укр» — лише вхід оракула.
Двійковий FPC аргумент будується окремо чинним senst5m, не текстом.
"""
import pathlib
import subprocess
import sys
import tempfile

def need(ok, why):
    if not ok:
        raise AssertionError(why)

def run(args, timeout=120):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=False)

def pack(packer, root, words, name):
    source = root / (name + ".words")
    source.write_text(" ".join(words) + "\n", encoding="ascii")
    outcome = run([packer, "--пакувати-слова", str(source)])
    need(outcome.returncode == 0 and outcome.stdout and
         b"0 unfreed memory blocks" in outcome.stderr,
         "FPC не пакує точні слова без витоків " + name + ": " +
         outcome.stderr.decode("utf-8", errors="replace"))
    return outcome.stdout

def verify(actual, upstream, physical_answers):
    # Рівно один upstream D1-предикат, ні D3:000, ні зайвий рядок.
    need(upstream in (b"0\n", b"1\n"), "oracle повернув не один D1")
    need(actual == physical_answers[upstream],
         "відмінність фактичної фізичної відповіді Core1 та SENS")

def main():
    need(len(sys.argv) == 5,
         "потрібні: senscore1vykon senst5m незалежний-sens корінь")
    native, packer, oracle = map(str, sys.argv[1:4])
    repo = pathlib.Path(sys.argv[4]).resolve()
    pin = repo / "external/sens/lib/core1.sens"
    projection = repo / "external/sens/lib/core1.lisp"
    independent = repo / "sens-oracle/lib/core1.lisp"
    for path in (pin, projection, independent):
        need(path.is_file(), "відсутній pinned Core1: " + str(path))
    need(projection.read_bytes() == independent.read_bytes(),
         "українська pinned проєкція не відповідає незалежному checkout")

    # Кожен рядок даних — exact D1:1/D1:0; довжина host 2..5,
    # НЕ числовий домен D12+ і НЕ прихована семантика D7.
    cases = [
        (1, 0), (0, 1), (1, 1), (0, 0),
        (1, 0, 1), (0, 1, 0), (1, 1, 0), (0, 0, 1),
        (1, 0, 0, 1), (0, 1, 1, 0), (1, 1, 1, 0), (0, 0, 0, 1),
        (1, 0, 1, 0, 1), (0, 1, 0, 1, 0), (1, 1, 0, 1, 0),
        (0, 0, 1, 0, 1),
    ]
    need(len(cases) == len(set(cases)) == 16,
         "дубльовані диференційні свідки")

    with tempfile.TemporaryDirectory(prefix="core1-diferentsiinyi-") as dirname:
        folder = pathlib.Path(dirname)
        answers = {
            b"0\n": pack(packer, folder, ["0"], "очікуваний-нуль"),
            b"1\n": pack(packer, folder, ["1"], "очікувана-одиниця"),
        }
        need(answers[b"0\n"] != answers[b"1\n"],
             "різні предикати злилися в одному фізичному слові")
        confirmed = []
        for number, values in enumerate(cases, start=1):
            label = "свідок-" + str(number)
            bits = list(map(str, values))
            # Реальна ФІЗИЧНА D4:1110 форма, яку приймає перше
            # замикання з pinned core1.sens; не створюємо Pascal
            # реалізацію другого елемента.
            argument = pack(packer, folder, ["10", "1110", *bits, "01"],
                            label + "-аргумент")
            argument_path = folder / (label + ".sens")
            argument_path.write_bytes(argument)
            physical = run([native, "--виконати-перший", str(repo),
                            str(argument_path)])
            need(physical.returncode == 0,
                 label + " FPC відхилив: " +
                 physical.stderr.decode("utf-8", errors="replace"))
            need(b"0 unfreed memory blocks" in physical.stderr,
                 label + " FPC heaptrc не засвідчив нуль витоків")

            # Шлях SENS ДІЙСНО завантажує усі бібліотечні DEFINE
            # та викликає перше через «укр» проєкцію, не лише
            # незалежний (D4:1001 ...).
            names = ["так" if value == 1 else "ні" for value in values]
            sentence = "(ядро1-другий-елемент (список " + (
                " ".join(names)) + "))\n"
            human_path = folder / (label + ".lisp")
            human_path.write_text(sentence, encoding="utf-8")
            oracle_answer = run([oracle, "--t5m-files", str(independent),
                                 str(human_path)])
            need(oracle_answer.returncode == 0 and
                 oracle_answer.stderr == b"",
                 label + " pinned REPL відхилив: " +
                 oracle_answer.stderr.decode("utf-8", errors="replace"))
            verify(physical.stdout, oracle_answer.stdout, answers)
            confirmed.append((physical.stdout, oracle_answer.stdout))

        # Негативи не повинні перетворювати компаратор на «завжди так».
        refused = [
            (confirmed[0][0], b"1\n"),  # правильний FPC, чужий transcript
            (confirmed[1][0], b"0\n"),
            (answers[b"0\n"], b"()\n"),  # D3 порожній не D1:0
            (answers[b"1\n"], b"1\n0\n"),  # другий рядок
            (answers[b"1\n"], b""),
            (answers[b"0\n"], b"0"),
            (answers[b"1\n"], "так\n".encode("utf-8")),
        ]
        for number, (physical, transcript) in enumerate(refused, 1):
            try:
                verify(physical, transcript, answers)
            except AssertionError:
                continue
            raise AssertionError("фальшивий transcript пройшов: " +
                                 str(number))

        # Транспортні негативи перевіряються тим самим реальним CLI.
        def reject(payload, label, extension=".sens", code=2):
            source = folder / ("негатив-" + label + extension)
            source.write_bytes(payload)
            result = run([native, "--виконати-перший", str(repo), str(source)])
            need(result.returncode == code,
                 label + " не відхилено правильним кодом")
            need(result.stdout == b"",
                 label + " опубліковано частковий фізичний результат")
            need(b"CORE1-" in result.stderr,
                 label + " відсутня діагностика")
            if code == 2:
                need(b"0 unfreed memory blocks" in result.stderr,
                     label + " витік після відмови")
        reject(bytes([243]), "хибний-т5м")
        reject(pack(packer, folder, ["10", "1110", "1", "01"],
                    "один-елемент"), "закороткий-список")
        reject(pack(packer, folder, ["10", "1110", "1", "0", "01"],
                    "людська-підміна"), "людська-підміна", ".lisp", 64)

        need(len(confirmed) == 16 and len(refused) == 7,
             "неповне покриття")
        print("CORE1-БАГАТОСВІДКОВИЙ-ОРАКУЛ-ГАРАЗД "
              "фізичних-замикань=16 незалежних-реальних-Core1=16 "
              "підробок-transcript=7 транспортних-негативів=3 "
              "T5M=побайтово heaptrc=нуль D7=бібліотечна-назва "
              "D12+=без-перетлумачення")
        print("МЕЖА: лише перша Core1-функція, без повного REPL/GC/runtime")

if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print("CORE1-БАГАТОСВІДКОВИЙ-ОРАКУЛ-ПРОВАЛ: " + str(error),
              file=sys.stderr)
        sys.exit(1)
