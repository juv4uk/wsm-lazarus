#!/usr/bin/env python3
"""Незалежний pinned SENS-оракул для одного живого фізичного D3-сеансу.

Обидва виконавці отримують ті самі фізичні T5M байти.
Людська проєкція не є семантичним оракулом.
"""
import pathlib
import struct
import subprocess
import sys
import tempfile


def require(ok, explanation):
    if not ok:
        raise AssertionError(explanation)


def invoke(args, data=None, timeout=60):
    return subprocess.run(args, input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout, check=False)


def pack(cli, directory, name, words):
    source = directory / (name + '.words')
    source.write_text(' '.join(words) + '\n', encoding='ascii')
    result = invoke([cli, '--пакувати-слова', str(source)])
    require(result.returncode == 0 and not result.stderr and result.stdout,
            'неможливо пакувати точні слова ' + name)
    return result.stdout


def framed(physical):
    return struct.pack('<I', len(physical)) + physical


def replies_from(data, count):
    replies = []
    offset = 0
    for i in range(count):
        require(offset + 9 <= len(data), 'неповний заголовок відповіді ' + str(i))
        status, word, length = struct.unpack_from('<BII', data, offset)
        offset += 9
        require(status in (0, 1) and 0 < length <= 65536,
                'хибний статус/довжина відповіді ' + str(i))
        require(offset + length <= len(data), 'обірвана відповідь ' + str(i))
        replies.append((status, word, data[offset:offset + length]))
        offset += length
    require(offset == len(data), 'зайвий фізичний host-кадр')
    return replies


def upstream(cli, directory, name, physical):
    # SENS виконує саме ці bytes .sens, без повторного mint через .lisp.
    path = directory / (name + '.sens')
    path.write_bytes(physical)
    result = invoke([cli, str(path)])
    require(result.returncode == 0 and not result.stderr,
            'pinned SENS відхилив фізичну форму ' + name)
    require(result.stdout in (b'0\n', b'1\n', b'()\n'),
            'невідомий/множинний результат SENS ' + name)
    return result.stdout


def compare(reply, transcript, physical_by_transcript):
    # Лише тестове зіставлення трьох точних результатів D1/D3.
    # Не створюємо новий evaluator або D12+/D7 coercion.
    require(transcript in (b'0\n', b'1\n', b'()\n'),
            'оракул повернув зайві або неочікувані байти')
    require(reply == (0, 0, physical_by_transcript[transcript]),
            'не збігаються фізичні відповіді FPC та незалежного SENS')


def main():
    require(len(sys.argv) == 4,
            'потрібні: sensfizseans senst5m pinned-sens-cli')
    session, packer, oracle = [str(pathlib.Path(p).resolve()) for p in sys.argv[1:]]
    for binary in (session, packer, oracle):
        require(pathlib.Path(binary).is_file(), 'не знайдено binary: ' + binary)

    with tempfile.TemporaryDirectory(prefix='sens-fiz-orakul-') as temporary:
        directory = pathlib.Path(temporary)
        physical = {
            b'0\n': pack(packer, directory, 'нуль-результат', ['0']),
            b'1\n': pack(packer, directory, 'один-результат', ['1']),
            b'()\n': pack(packer, directory, 'порожній-результат', ['000']),
        }
        examples = [
            ('нуль', physical[b'0\n']),
            ('цитата', pack(packer, directory, 'цитата', ['10', '001', '1', '01'])),
            ('один', physical[b'1\n']),
            ('порожній', physical[b'()\n']),
            ('знову-нуль', physical[b'0\n']),
        ]
        independent = [upstream(oracle, directory, name, source)
                       for name, source in examples]
        require(independent == [b'0\n', b'1\n', b'1\n', b'()\n', b'0\n'],
                'upstream Contract 12 змінив фізичні свідки')

        # 6 host-кадрів у тому самому процесі: 5 форм + 1 відмова.
        sources = [examples[0][1], bytes([243])] + [source for _, source in examples[1:]]
        process = invoke([session, '--сеанс'], b''.join(map(framed, sources)))
        require(process.returncode == 0 and process.stderr == b'',
                'FPC сеанс завершився після відхиленої форми')
        replies = replies_from(process.stdout, len(sources))
        status, word, diagnostic = replies[1]
        require(status == 1 and word == 0 and bool(diagnostic),
                'пошкоджений T5M не дав точну фізичну відмову')
        valid = replies[:1] + replies[2:]
        for (name, _), answer, transcript in zip(examples, valid, independent):
            try:
                compare(answer, transcript, physical)
            except AssertionError as error:
                raise AssertionError(name + ': ' + str(error)) from error

        # Негативи компаратора не дозволяють часткового збігу.
        bad = [
            ((0, 0, physical[b'1\n']), b'0\n'),
            ((1, 0, physical[b'0\n']), b'0\n'),
            ((0, 1, physical[b'0\n']), b'0\n'),
            (valid[0], b'0\n1\n'),
            (valid[0], b''),
            (valid[0], 'НІ\n'.encode('utf-8')),
            ((0, 0, pack(packer, directory, 'не-d1', ['000000000000'])), b'0\n'),
        ]
        for i, (fake, transcript) in enumerate(bad):
            try:
                compare(fake, transcript, physical)
            except AssertionError:
                continue
            raise AssertionError('компаратор допустив негатив ' + str(i + 1))
        require(len(valid) == 5 and len(bad) == 7, 'неповна перевірка')

        print('ФІЗИЧНИЙ-СЕАНС-ОРАКУЛ-ГАРАЗД форм=5 відмов=1 '
              'негативів=7 pinned=Contract12 .sens=однакові '
              'FPC-сеанс=один-процес upstream=незалежний')
        print('МЕЖА: Core4=не-перевірено REPL=не-повний '
              'D7=дані D12+=без-перетлумачення')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print('ФІЗИЧНИЙ-СЕАНС-ОРАКУЛ-ПРОВАЛ: ' + str(error), file=sys.stderr)
        sys.exit(1)
