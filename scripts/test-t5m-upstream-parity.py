#!/usr/bin/env python3
"""G1.21: диференційний транспорт T5M FPC ↔ pinned SENS, не семантика.

Oracle — ЖИВИЙ Python module, прочитаний git show із pinned commit
з перевіреним Git blob SHA; жодної копії законів/кодека всередині тесту.
Справжній FPC CLI працює з фізичними .sens байтами, не з Lisp ASCII.
"""
from __future__ import annotations

import argparse
import importlib.util
import random
import subprocess
import sys
import tempfile
from pathlib import Path

SEED = 20261029
ORACLE_BLOB_SHA = "e8b92ced6fb1b8d7c18ab397ed2a1a00432e923e"
WIDTHS = (1, 2, 3, 7, 9, 10, 11, 12, 24, 48, 96, 192, 1024, 8192)


def require(condition: bool, description: str) -> None:
    if not condition:
        raise AssertionError(description)


def call(cli: str, option: str, filename: Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [cli, option, str(filename)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def oracle_module(path: Path):
    spec = importlib.util.spec_from_file_location("pinned_sens_t5m_codec", path)
    require(spec is not None and spec.loader is not None, "не знайдено pinned codec")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    require(hasattr(module, "encode_t5m_projection"), "upstream encoder відсутній")
    require(hasattr(module, "decode_t5m_bytes"), "upstream decoder відсутній")
    return module


def exact_words() -> list[list[str]]:
    """Фіксована відтворювана добірка, включно з різним padding і D12+.

    Width у цьому тесті — ТІЛЬКИ фізична довжина, НЕ Dn admission.
    """
    cases = [
        ["0"], ["1"], ["00000"], ["11111"],
        ["10", "01"], ["10", "00", "01"], ["0", "00", "000"],
        ["00000000", "000000000"], ["001", "000"],
        ["101010101010101010101010"],
        ["0" * 12], ["1" * 12], ["0" * 24], ["1" * 48],
        ["0" * 96], ["1" * 192], ["01" * 512],
        ["0" * 8192], ["1" * 8192],
    ]
    # 5 різних залишків довжини тритів (padding від 0 до 4).
    for n in range(1, 16):
        cases.append(["0" * n])
        cases.append(["1" * n, "0"])
    random = __import__("random").Random(SEED)
    for index in range(168):
        count = random.randint(1, 24)
        words: list[str] = []
        for word_index in range(count):
            width = random.choice(WIDTHS)
            if width == 8192 and index % 17 != 0:
                width = 24
            if index % 23 == 0 and word_index == 0:
                width = (12, 24, 48, 96, 192)[index % 5]
            words.append("".join(random.choices("01", k=width)))
        cases.append(words)
    return cases


def check_positive(cli: str, codec, directory: Path) -> int:
    view = directory / "вхід.words"
    physical = directory / "фізичний.sens"
    positive = 0
    for index, words in enumerate(exact_words(), 1):
        expected = codec.encode_t5m_projection(" ".join(words))
        require(codec.decode_t5m_bytes(expected) == words,
                f"pinned upstream self roundtrip #{index}")
        view.write_bytes((" ".join(words) + "\n").encode("ascii"))

        packed = call(cli, "--пакувати-слова", view)
        require(packed.returncode == 0,
                f"FPC pack #{index} exit={packed.returncode}: {packed.stderr[-500:]!r}")
        require(packed.stdout == expected,
                f"FPC vs pinned SENS physical bytes #{index}: "
                f"widths={[len(w) for w in words]}, "
                f"got={packed.stdout[:24].hex()} expected={expected[:24].hex()}")
        physical.write_bytes(expected)

        unpacked = call(cli, "--перегляд", physical)
        require(unpacked.returncode == 0,
                f"FPC view #{index} exit={unpacked.returncode}: {unpacked.stderr[-500:]!r}")
        require(unpacked.stdout == view.read_bytes(),
                f"FPC view exact words/widths #{index}: {[len(w) for w in words]}")
        require(codec.decode_t5m_bytes(packed.stdout) == words,
                f"upstream decoder rejected FPC stdout #{index}")
        positive += 1
    return positive


def physical_negatives(codec) -> list[tuple[str, bytes]]:
    # Невалідні байти, порожній потік, стартовий/подвійний separator,
    # тільки кінцевий padding, повторений separator після слова.
    result: list[tuple[str, bytes]] = [
        ("порожній", b""),
        ("лише-заповнення", bytes([242])),
        ("початковий-роздільник", bytes([162])),
        ("повторний-роздільник", bytes([72])),
        ("після-завершення-слова", bytes([80, 0])),
    ]
    result.extend((f"заборонений-байт-{n}", bytes([n])) for n in range(243, 256))
    for name, data in result:
        try:
            codec.decode_t5m_bytes(data)
        except codec.SensT5Error:
            continue
        raise AssertionError(f"upstream oracle не відхилив: {name}")
    return result


def check_negative(cli: str, codec, directory: Path) -> tuple[int, int]:
    physical = directory / "поганий.sens"
    view = directory / "поганий.words"
    rejected_physical = 0
    for name, data in physical_negatives(codec):
        physical.write_bytes(data)
        outcome = call(cli, "--перегляд", physical)
        require(outcome.returncode != 0 and outcome.stdout == b"",
                f"FPC malformed physical accepted/partial stdout: {name}")
        require(b"SENST5M-FAIL" in outcome.stderr,
                f"відсутня FPC діагностика: {name}")
        rejected_physical += 1

    # CLI формат words суворіший за upstream parse_t5m_words:
    # перевіряється host-ввід (один LF, тільки один пробіл).
    invalid_views = [
        b"", b"10  01\n", b" 10\n", b"10 \n", b"10 01",
        b"10\t01\n", b"10\r\n", b"10 2\n",
        b"10 01\n\n", b"10 0X1\n", b"10\x0001\n",
    ]
    rejected_views = 0
    for data in invalid_views:
        view.write_bytes(data)
        outcome = call(cli, "--пакувати-слова", view)
        require(outcome.returncode != 0 and outcome.stdout == b"",
                f"FPC malformed word-view accepted/partial stdout: {data!r}")
        require(b"SENST5M-FAIL" in outcome.stderr,
                f"відсутня FPC діагностика word-view: {data!r}")
        rejected_views += 1
    return rejected_physical, rejected_views



def check_exhaustive_bytes(cli: str, codec, directory: Path) -> tuple[int, int, int, int]:
    """Усі однобайтові T5M та 64 межі між байтами проти pinned oracle.

    Raw bytes — позичені Python bytes; тимчасові файли належать TemporaryDirectory.
    Повертаємо чотири host-лічильники, НЕ значення SENS чи доменні коди.
    Немає окремого декодера: класифікацію робить живий pinned SENS codec.

    Питання: чому W7 не стає функцією від успішного transport?
    Чому допустимий W12 не означає числовий закон D12?
    Чому відхилення мусить залишати stdout порожнім?
    Чому двобайтовий стик може відрізнятися від двох окремих файлів?
    """
    physical = directory / "вичерпний-байт.sens"
    view = directory / "вичерпний-перегляд.words"

    def check_case(name: str, data: bytes) -> bool:
        try:
            words = codec.decode_t5m_bytes(data)
        except codec.SensT5Error:
            words = None
        physical.write_bytes(data)
        result = call(cli, "--перегляд", physical)
        if words is None:
            require(result.returncode != 0 and result.stdout == b"",
                    f"{name}: пошкоджений фізичний T5M прийнято або є частковий stdout")
            require(b"SENST5M-FAIL" in result.stderr,
                    f"{name}: немає FPC діагностики: {result.stderr[-300:]!r}")
            return False

        expected_view = (" ".join(words) + "\n").encode("ascii")
        require(result.returncode == 0 and result.stdout == expected_view,
                f"{name}: FPC перегляд не дорівнює pinned словам/ширинам; "
                f"вихід={result.stdout[:80]!r}, очікується={expected_view[:80]!r}")
        view.write_bytes(expected_view)
        repacked = call(cli, "--пакувати-слова", view)
        require(repacked.returncode == 0 and repacked.stdout == data,
                f"{name}: FPC byte-exact round-trip не збігся; "
                f"одержано={repacked.stdout.hex()} очікується={data.hex()}")
        return True

    valid_one = invalid_one = 0
    for byte in range(256):
        if check_case(f"байт-{byte:03d}", bytes([byte])):
            valid_one += 1
        else:
            invalid_one += 1
    require((valid_one, invalid_one) == (138, 118),
            f"неповний однобайтовий перепис T5M: {valid_one}/{invalid_one}")

    # Включно з D2-подібним W2 53/100, separator 72/161,
    # останнім канонічним 242 та забороненим 243; числа тут не тлумачимо.
    boundaries = (0, 53, 72, 80, 100, 161, 242, 243)
    valid_two = invalid_two = 0
    for first in boundaries:
        for second in boundaries:
            if check_case(f"стик-{first:03d}-{second:03d}", bytes([first, second])):
                valid_two += 1
            else:
                invalid_two += 1
    require(valid_two > 0 and invalid_two > 0 and valid_two + invalid_two == 64,
            "двобайтові стики не перевірено повністю")
    return valid_one, invalid_one, valid_two, invalid_two



def check_late_physical_corruption(
    cli: str, codec, directory: Path
) -> tuple[int, int, int]:
    """Пізній недопустимий байт не публікує вже підготовлений T5M-вихід.

    Prefix/suffix: позичені незмінні bytes, без реєстру доменних законів.
    Файли тимчасові; кожен subprocess володіє лише власною відповіддю.
    Повертаємо host-лічильники відмов у перегляді, D2 і відновлень.

    Питання: чому W7:0010110 — дані, навіть якщо це pinned SYN?
    Чому W12/W24 не надає арифметичної семантики без точного домену?
    Чому відмова наприкінці не має публікувати жодного рядка?
    Чому structural admission W1..W9 не перевіряє викличність?
    """
    physical = directory / "пізнє-пошкодження.sens"
    # Структурний CLI навмисне має вузьку квоту W1..W9. W12+
    # перевіряємо ЛИШЕ на транспортному рівні; D12 не вгадуємо.
    witnesses: tuple[tuple[str, list[str], bool], ...] = (
        ("д1-нуль", ["0"], True),
        ("д1-одиниця", ["1"], True),
        ("д3-порожнє", ["000"], True),
        ("д2-порожній-список", ["10", "01"], True),
        ("д2-список", ["10", "1", "000", "01"], True),
        ("д2-крапкова-пара", ["10", "0", "11", "1", "01"], True),
        ("д7-syn-як-дані", ["10", "0010110", "01"], True),
        ("три-корені", ["0", "1", "000"], True),
        ("w12-не-d12", ["0" * 12], False),
        ("w24-не-d24", ["1" * 24], False),
        ("w192-не-d192", ["0" * 191 + "1"], False),
    )
    bad_views = bad_structures = recoveries = 0
    for name, words, can_check_structure in witnesses:
        good = codec.encode_t5m_projection(" ".join(words))
        require(codec.decode_t5m_bytes(good) == words,
                f"{name}: pinned canonical prefix не відтворив слова")
        expected = (" ".join(words) + "\\n").encode("ascii")
        modes = [("--перегляд", expected)]
        if can_check_structure:
            modes.append(("--перевірити-структуру", None))
        physical.write_bytes(good)
        for option, exact_output in modes:
            baseline = call(cli, option, physical)
            require(baseline.returncode == 0,
                    f"{name}/{option}: валідний префікс відхилено: "
                    f"{baseline.stderr[-300:]!r}")
            if exact_output is None:
                require(baseline.stdout.startswith(
                    "СТРУКТУРА-ГАРАЗД ".encode("utf-8")),
                    f"{name}/{option}: немає фізичного D2 підтвердження")
            else:
                require(baseline.stdout == exact_output,
                        f"{name}/{option}: змінено точні біти валідного префікса")
            # 243..255 фізично неможливі як один T5M-байт.
            # Після вже прочитаних правильних слів заборонено partial stdout.
            for poison in range(243, 256):
                damaged = good + bytes([poison])
                try:
                    codec.decode_t5m_bytes(damaged)
                except codec.SensT5Error:
                    pass
                else:
                    raise AssertionError(
                        f"{name}: pinned decoder прийняв пізній байт {poison}")
                physical.write_bytes(damaged)
                failure = call(cli, option, physical)
                require(failure.returncode != 0 and failure.stdout == b"",
                        f"{name}/{option}/{poison}: FPC прийняв зіпсований "
                        "файл або опублікував частковий stdout")
                require(b"SENST5M-FAIL" in failure.stderr,
                        f"{name}/{option}/{poison}: загублено діагностику")
                require(physical.read_bytes() == damaged,
                        f"{name}/{option}/{poison}: CLI змінив вхідний .sens")
                if option == "--перегляд":
                    bad_views += 1
                else:
                    bad_structures += 1

                physical.write_bytes(good)
                recovered = call(cli, option, physical)
                require(recovered.returncode == 0 and
                        recovered.stdout == baseline.stdout,
                        f"{name}/{option}/{poison}: порушено наступний "
                        "незалежний коректний запуск")
                recoveries += 1
    return bad_views, bad_structures, recoveries


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--oracle", type=Path, required=True)
    parser.add_argument("--cli", type=Path, required=True)
    args = parser.parse_args()
    codec = oracle_module(args.oracle.resolve())
    cli = str(args.cli.resolve())
    require(args.cli.is_file(), "FPC CLI відсутній")
    with tempfile.TemporaryDirectory(prefix="сенс-т5м-") as temporary:
        directory = Path(temporary)
        positive = check_positive(cli, codec, directory)
        negative_physical, negative_views = check_negative(cli, codec, directory)
        byte_ok, byte_bad, seam_ok, seam_bad = check_exhaustive_bytes(cli, codec, directory)
        late_view, late_d2, recovered = check_late_physical_corruption(
            cli, codec, directory
        )
    require(positive >= 200, "мало незалежних фізичних свідків")
    require(negative_physical >= 18 and negative_views >= 11,
            "недостатньо негативних свідків")
    print(
        f"Т5М-UPSTREAM-ПАРИТЕТ-ГАРАЗД "
        f"фізичних={positive} відхилено-байтових={negative_physical} "
        f"відхилено-проєкцій={negative_views} "
        f"байти={byte_ok}/{byte_bad} стики={seam_ok}/{seam_bad} "
        f"пізні-помилки={late_view}/{late_d2} відновлень={recovered} "
        f"seed={SEED} кодек-blob={ORACLE_BLOB_SHA} "
        f"д12+=тільки-фізичні-слова семантика=НЕ-ДОВЕДЕНА"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, subprocess.TimeoutExpired, OSError) as error:
        print(f"Т5М-UPSTREAM-ПАРИТЕТ-ПОМИЛКА: {error}", file=sys.stderr)
        sys.exit(1)
