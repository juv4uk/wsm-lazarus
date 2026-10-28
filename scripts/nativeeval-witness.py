#!/usr/bin/env python3
"""G3.2: фізичні .sens/T5M-свідки з exact pin; не старий текстовий oracle."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
POSITIVE = [
    '()', 'так', 'ні', '(як-є ())', '(як-є (()))', '(як-є кіт)',
    '(як-є так)', '(як-є (кіт пес))',
    '(перше (як-є (кіт пес)))', '(решта (як-є (кіт пес)))',
    '(сполучити так ())', '(сполучити так ні)',
    '(перше (сполучити ні ()))', '(решта (сполучити так ()))',
    '(атом? ())', '(атом? ні)', '(атом? (як-є (кіт)))',
    '(атом? (перше (сполучити ні ())))', '(атом? (сполучити так ()))',
]
NEGATIVE = [
    ('(перше ())', b'car expects a non-empty list'),
    ('(решта ні)', b'cdr expects a non-empty list'),
    ('(сполучити так)', b'111: expected 2 arguments; received 1'),
    ('(як-є)', b'D3:001: expected'),
    ('(атом? так ні)', b'010: expected 1 arguments; received 2'),
]


def run(argv, cwd=ROOT):
    return subprocess.run([str(x) for x in argv], cwd=cwd,
                          capture_output=True, timeout=30)


def git(root, *args):
    p = run(['git', *args], root)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors='replace'))
    return p.stdout.decode().strip()


def matches_result(witness, native, accepted, expected_error=b''):
    if accepted:
        return (witness.returncode == native.returncode == 0
                and witness.stdout == native.stdout)
    return (bool(expected_error) and witness.returncode == 1
            and witness.stdout == b''
            and witness.stderr.startswith(b'sens: current SENS execution rejected: ')
            and expected_error in witness.stderr
            and b'[physical_form_index=0 ' in witness.stderr
            and native.returncode == 2 and native.stdout == b''
            and b'NATIVEEVAL-ERROR line=' in native.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--sens-root', type=Path, required=True)
    ap.add_argument('--fpc', default=os.environ.get('FPC', 'fpc'))
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    args.out = args.out.resolve()
    sens_root = args.sens_root.resolve()
    pin = next(line.split('=', 1)[1] for line in
               (ROOT/'refs/tier1-baseline.properties').read_text().splitlines()
               if line.startswith('MY_LISP_PIN='))
    if git(sens_root, 'rev-parse', 'HEAD') != pin:
        raise RuntimeError('SENS_SOURCE_PIN_MISMATCH')
    if git(sens_root, 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('SENS_SOURCE_DIRTY')
    if git(ROOT/'external/sens', 'rev-parse', 'HEAD') != pin:
        raise RuntimeError('LAZARUS_AUTHORITY_PIN_MISMATCH')
    if git(ROOT/'external/sens', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('LAZARUS_AUTHORITY_DIRTY')
    contract = run(['git', 'show', 'HEAD:contracts/language-contract-12.lisp'], sens_root)
    if contract.returncode or b'sens-language-contract-12/1' not in contract.stdout:
        raise RuntimeError('CURRENT_DOMAIN_CONTRACT_MISSING')
    cli = sens_root/'target/release/sens'
    native_binary = ROOT/'build/m0.2/bin/test-nativeeval'
    source_hash = hashlib.sha256((ROOT/'src/wsm.nativeeval.pas').read_bytes()).hexdigest()
    records = []
    args.out.mkdir(parents=True, exist_ok=True)
    build = run(['env', f'FPC={args.fpc}', 'bash', ROOT/'scripts/test-nativeeval.sh'])
    (args.out/'native-build.log').write_bytes(build.stdout+build.stderr)
    if build.returncode or not native_binary.is_file():
        raise RuntimeError('NATIVE_BUILD_OR_TEST_FAILED')
    if source_hash != hashlib.sha256((ROOT/'src/wsm.nativeeval.pas').read_bytes()).hexdigest():
        raise RuntimeError('NATIVE_SOURCE_CHANGED_DURING_BUILD')
    try:
        with tempfile.TemporaryDirectory(prefix='nativeeval-t5m-') as temp:
            for i, (source, accepted, expected_error) in enumerate(
                    [(s, True, b'') for s in POSITIVE]+
                    [(s, False, error) for s, error in NEGATIVE]):
                stem = Path(temp)/f'case-{i:02d}'
                text = stem.with_suffix('.lisp')
                physical = stem.with_suffix('.sens')
                text.write_text(source+'\n', encoding='utf-8')
                minted = run([cli, '--t5m-mint', text, physical])
                if minted.returncode or not physical.is_file():
                    raise RuntimeError(f'PHYSICAL_WITNESS_NOT_MINTED case={i}: '
                                       +minted.stderr.decode(errors='replace'))
                data = physical.read_bytes()
                if not data or data == text.read_bytes():
                    raise RuntimeError('PHYSICAL_CARRIER_REQUIRED')
                # Виконується фізичний carrier, не текстова форма у REPL.
                witness = run([cli, physical])
                native = run([native_binary, ROOT/'external/sens', '--eval', source])
                matched = matches_result(witness, native, accepted, expected_error)
                (args.out/f'{i:02d}.sens').write_bytes(data)
                records.append({'source_projection': source, 'positive': accepted,
                                'expected_error_fragment': expected_error.decode(),
                                'physical_sha256': hashlib.sha256(data).hexdigest(),
                                'sens_exit': witness.returncode,
                                'native_exit': native.returncode,
                                'sens_stdout': witness.stdout.decode(errors='replace'),
                                'native_stdout': native.stdout.decode(errors='replace'),
                                'sens_stderr': witness.stderr.decode(errors='replace'),
                                'native_stderr': native.stderr.decode(errors='replace'),
                                'matched': matched})
                if not matched:
                    raise RuntimeError(f'PHYSICAL_PARITY_FAILED case={i}')
    finally:
        doc = {'schema': 'lazarus-native-d3-physical-witness/v1',
               'sens_pin': pin, 'lazarus_base_sha': git(ROOT, 'rev-parse', 'HEAD'),
               'native_source_sha256': source_hash,
               'sens_binary_sha256': hashlib.sha256(cli.read_bytes()).hexdigest(),
               'native_binary_sha256': hashlib.sha256(native_binary.read_bytes()).hexdigest(),
               'native_build': 'fresh FPC compile and tests inside gate; native-build.log',
               'sens_binary_provenance': 'SHA256 identifies binary; source-to-binary build not certified by this script',
               'route': 'source-projection -> pinned Zig/T5M mint -> physical .sens execution',
               'authority': 'pinned SENS Contract 12.0; no text oracle or flat-byte fallback',
               'scope': 'five D3 mechanisms, D1 values, bounded D7 letter projection',
               'core4_execution': 'NOT_IMPLEMENTED',
               'records': records}
        (args.out/'witness.json').write_text(json.dumps(doc, ensure_ascii=False, indent=2)+'\n')
    print(f'NATIVEEVAL-PHYSICAL-OK positive={len(POSITIVE)} negative={len(NEGATIVE)} '
          f'pin={pin} route=T5M-exact-domain')


if __name__ == '__main__':
    main()
