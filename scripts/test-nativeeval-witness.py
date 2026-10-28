#!/usr/bin/env python3
"""Негативи proof gate: збій процесу не є семантичною відмовою."""
import importlib.util
from pathlib import Path
import subprocess
import unittest

spec=importlib.util.spec_from_file_location('witness',Path(__file__).with_name('nativeeval-witness.py'))
witness=importlib.util.module_from_spec(spec)
spec.loader.exec_module(witness)
PREFIX=b'sens: current SENS execution rejected: '
ERROR=b'car expects a non-empty list'
POSITION=b' [physical_form_index=0 physical_word_start=0 physical_word_end=5]\n'

def proc(code,stdout=b'',stderr=b''):
    return subprocess.CompletedProcess([],code,stdout,stderr)

class EvidenceGateTests(unittest.TestCase):
    def setUp(self):
        self.native=proc(2,stderr=b'NATIVEEVAL-ERROR line=1 column=1 byte=1 failure\n')
    def test_named_physical_error_is_accepted(self):
        self.assertTrue(witness.matches_result(proc(1,stderr=PREFIX+ERROR+POSITION),self.native,False,ERROR))
    def test_signals_never_count_as_semantic_rejection(self):
        for signal in [-11,-9,-6]:
            with self.subTest(signal=signal):
                self.assertFalse(witness.matches_result(proc(signal,stderr=PREFIX+ERROR+POSITION),self.native,False,ERROR))
    def test_loader_crash_and_unrelated_error_are_rejected(self):
        for code,msg in [(127,b'loader failed'),(1,b'Segmentation fault'),(1,PREFIX+b'unknown runtime failure'+POSITION)]:
            with self.subTest(code=code,msg=msg):
                self.assertFalse(witness.matches_result(proc(code,stderr=msg),self.native,False,ERROR))
    def test_error_requires_physical_source_location(self):
        self.assertFalse(witness.matches_result(proc(1,stderr=PREFIX+ERROR),self.native,False,ERROR))
    def test_failed_run_must_not_emit_a_value(self):
        self.assertFalse(witness.matches_result(proc(1,stdout=b'()\n',stderr=PREFIX+ERROR+POSITION),self.native,False,ERROR))
    def test_native_signal_is_rejected(self):
        self.assertFalse(witness.matches_result(proc(1,stderr=PREFIX+ERROR+POSITION),proc(-11),False,ERROR))
    def test_positive_requires_exact_output_and_success(self):
        self.assertTrue(witness.matches_result(proc(0,b'1\n'),proc(0,b'1\n'),True))
        self.assertFalse(witness.matches_result(proc(0,b'1\n'),proc(0,b'0\n'),True))
        self.assertFalse(witness.matches_result(proc(1,b'1\n'),proc(0,b'1\n'),True))

if __name__=='__main__': unittest.main()
