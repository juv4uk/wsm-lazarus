#!/usr/bin/env python3
# G1.51: наскрізний доказ 95 друкованих D7-координат у п'яти pinned поверхнях.
# Уся семантика живе в pinned SENS; цей тест працює лише з даними й T5M.
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
CODEC_BLOB = "e8b92ced6fb1b8d7c18ab397ed2a1a00432e923e"
COLS = ("ук", "укр", "san", "en", "LISP", "sym")
PRINT_COLS = ("ук", "укр", "san", "en", "sym")


def execute(*args, status=0):
    """Виклик окремого host-процесу; байти stdout є власністю викликача."""
    result = subprocess.run([str(a) for a in args], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=60, check=False)
    if result.returncode != status:
        raise AssertionError(
            f"код {result.returncode}, очікувано {status}; argv={args}; "
            f"stderr={result.stderr[:1200]!r}")
    if status == 2:
        if result.stdout:
            raise AssertionError(f"частковий stdout після відмови: {args}")
        if "РЯДКИ-Д7-ВІДМОВА:".encode() not in result.stderr:
            raise AssertionError(f"немає діагностики відмови: {args}")
    elif result.stderr:
        raise AssertionError(f"несподіваний stderr: {args}: {result.stderr[:1200]!r}")
    return result.stdout


def catalog_from_existing_fpc(viewer):
    """Читаємо повний уже перевірений FPC каталог; НЕ парсимо .lisp вдруге."""
    raw = execute(viewer, "external/sens", "--домен", "7")
    lines = raw.decode("utf-8", errors="strict").splitlines()
    if len(lines) != 128 * 7:
        raise AssertionError(f"не 128 рядків по сім полів: {len(lines)}")
    rows = []
    for number in range(128):
        start = number * 7
        bits = format(number, "07b")
        if lines[start] != f"координата: D7:{bits}":
            raise AssertionError(f"змінено exact W7 координату {number}")
        row = {}
        for j, column in enumerate(COLS, 1):
            prefix = f"{column}: "
            field = lines[start + j]
            if not field.startswith(prefix):
                raise AssertionError(f"відсутня колонка {column} для {bits}")
            row[column] = field[len(prefix):]
        if row["LISP"] != "()":
            raise AssertionError(f"D7: {bits} помилково отримав викличну проєкцію")
        rows.append((bits, row))
    for number, (_, row) in enumerate(rows):
        printable = 32 <= number <= 126
        for column in PRINT_COLS:
            if (row[column] != "()") != printable:
                raise AssertionError(f"зіпсована D7 координата {number} {column}")
    return rows


def pinned_upstream_codec(tmpdir):
    """Отримати незалежний кодек без зміни gitlink та без другого reader."""
    content = execute("git", "-C", "external/sens", "show",
                      f"{PIN}:scripts/sens_t5_t5m_codec.py")
    source = tmpdir / "pinned-codec.py"
    source.write_bytes(content)
    digest = execute("git", "hash-object", source).decode().strip()
    if digest != CODEC_BLOB:
        raise AssertionError(f"не той pinned codec blob: {digest}")
    spec = importlib.util.spec_from_file_location("pinned_t5m_d7_matrix", source)
    if spec is None or spec.loader is None:
        raise AssertionError("не завантажився pinned незалежний кодек")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if len(sys.argv) != 2:
        raise SystemExit("використання: test-d7-povna-matrytsia.py <FPC_BIN_DIR>")
    binaries = Path(sys.argv[1]).resolve()
    viewer = binaries / "sensproekcii"
    converter = binaries / "sensriadkyd7"
    packer = binaries / "senst5m"
    if not all(path.is_file() for path in (viewer, converter, packer)):
        raise AssertionError("відсутні реальні FPC виконувані файли")

    rows = catalog_from_existing_fpc(viewer)
    printable = rows[32:127]
    bits = [item[0] for item in printable]
    with tempfile.TemporaryDirectory(prefix="d7-povna-matrytsia-") as folder:
        tmp = Path(folder)
        words_path = tmp / "точні-слова.txt"
        words_path.write_bytes((" ".join(bits) + "\n").encode("ascii"))
        physical = execute(packer, "--пакувати-слова", words_path)
        if not physical:
            raise AssertionError("порожні фізичні байти W7")
        oracle = pinned_upstream_codec(tmp)
        if oracle.encode_t5m_projection(" ".join(bits)) != physical:
            raise AssertionError("FPC T5M != незалежний pinned SENS T5M")
        if oracle.decode_t5m_bytes(physical) != bits:
            raise AssertionError("pinned codec не відновив 95 точних W7")
        expected = tmp / "95-еталон.sens"
        expected.write_bytes(physical)

        # П'ять повних незалежних round-trip серій: одна фізична тотожність.
        for column in PRINT_COLS:
            tokens = [row[column] for _, row in printable]
            if len(tokens) != 95 or len(set(tokens)) != 95:
                raise AssertionError(f"колізія або не 95 поверхонь: {column}")
            token_bytes = ("\n".join(tokens) + "\n").encode("utf-8")
            source = tmp / f"{column}.txt"
            source.write_bytes(token_bytes)
            packed = execute(converter, "external/sens",
                             "--пакувати", column, source)
            if packed != physical:
                raise AssertionError(f"втрата точних packed байтів: {column}")
            candidate = tmp / f"{column}.sens"
            candidate.write_bytes(packed)
            restored = execute(converter, "external/sens",
                               "--розгорнути", column, candidate)
            if restored != token_bytes:
                raise AssertionError(f"текстова D7 проєкція не оборотна: {column}")
            again = tmp / f"{column}-знов.txt"
            again.write_bytes(restored)
            if execute(converter, "external/sens", "--пакувати",
                       column, again) != physical:
                raise AssertionError(f"повторне пакування змінило W7: {column}")

        # Негативна матриця: навіть після 95 коректних слів немає stdout.
        late_syn = tmp / "пізній-syn.sens"
        late_syn.write_bytes(execute(packer, "--пакувати-слова",
            write_words(tmp, bits + ["0010110"], "syn.txt")))
        late_d12 = tmp / "пізній-d12.sens"
        late_d12.write_bytes(execute(packer, "--пакувати-слова",
            write_words(tmp, bits + ["000000000000"], "d12.txt")))
        execute(converter, "external/sens", "--розгорнути",
                "укр", late_syn, status=2)
        execute(converter, "external/sens", "--розгорнути",
                "укр", late_d12, status=2)
        execute(converter, "external/sens", "--розгорнути",
                "LISP", expected, status=2)

        bad_text = tmp / "пізня-помилка.txt"
        bad_text.write_bytes((("\n".join(row["укр"] for _, row in printable))
                               + "\nНЕМАЄ-ТАКОЇ-D7-ПРОЄКЦІЇ\n").encode("utf-8"))
        execute(converter, "external/sens", "--пакувати",
                "укр", bad_text, status=2)
        execute(converter, "external/sens", "--пакувати",
                "LISP", bad_text, status=2)
        fake_lisp = tmp / "не-канон.lisp"
        fake_lisp.write_bytes(physical)
        execute(converter, "external/sens", "--розгорнути",
                "укр", fake_lisp, status=2)
        # Провал не змінює pinned таблиці чи стан наступного процесу.
        if execute(converter, "external/sens", "--розгорнути",
                   "укр", expected) != (("\n".join(
                   row["укр"] for _, row in printable)) + "\n").encode("utf-8"):
            raise AssertionError("після негативів D7 не відновився")
        print("Д7-ПОВНА-МАТРИЦЯ-ГАРАЗД точних=95 поверхонь=5 "
              "перевірених-токенів=475 oracle=pinned-T5M "
              "негативів=6 частковий-stdout=0")


def write_words(directory, words, name):
    """Масив уже кваліфікованих тестових Wn; це не числова арифметика."""
    path = directory / name
    path.write_bytes((" ".join(words) + "\n").encode("ascii"))
    return path


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, UnicodeError, subprocess.TimeoutExpired) as exc:
        print(f"Д7-ПОВНА-МАТРИЦЯ-ПОМИЛКА: {exc}", file=sys.stderr)
        sys.exit(1)
