#!/usr/bin/env bash
# G6: спільний x86-64 стековий STORE/LOAD для spill-слотів.
# Чинний тест сам будує справжній FPC 3.2.2 і виконує два ELF64.
# GNU as звіряє 66 машинних інструкцій незалежно від Pascal-кодера.
# Це host lowering-механізм, не закон SENS або вхідний .lisp.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
timeout 330s bash scripts/test-x64stack.sh
echo 'X64-STACK-STORE-PASS fpc=checked gnu-as=66 store=21 golden=6 negative=20 recovery=20 elf=2 physical-d1=2 oracle=NOT-RUN energy=NOT-MEASURED'
