#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Незалежний оракул-модель для свідка замикань (задача #866).

НАВІЩО: свідок scripts/test-zamykannia-svidok.pas викликає сам механізм
(src/wsm.nativeeval.pas), тому його вивід — не доказ правильності, а лише
спостереження. Щоб відрізнити «механізм працює» від «механізм повертає
те, що повертає», потрібна ДРУГА реалізація тих самих законів, написана
іншою мовою, без жодного спільного рядка коду з Pascal-обчислювачем.

ЩО ЦЕ ЗА РЕАЛІЗАЦІЯ: мінімальна аліста-модель, виведена з pinned джерел
juv4uk/sens (external/sens, пін фіксує scripts/check-pin.sh):
  * поєднати-параметри — external/sens/lib/core1.lisp:190-206
    (порожні параметри + порожні значення -> оточення;
     порожні параметри, але є значення -> ARITY TOO-MANY-ARGUMENTS;
     є параметри, але немає значень -> ARITY TOO-FEW-ARGUMENTS);
  * виконати-виклик-ядра / застосувати — core1.lisp:308-330
    (значення D4 FUNCTION уже є замиканням; виклик = тіло в новому
     оточенні, збудованому поєднати-параметри над захопленим оточенням);
  * мітка — external/sens/lib/domains/d5.lisp:13 (D5:00100);
  * створити-лямбда-замикання — external/sens/lib/domains/d10.lisp:327
    (D10:0100111100).
Модель НЕ читає Pascal-код і не викликає його: вона рахує очікування сама.

ЦЕ НЕ АВТОРИТЕТ. Справжній незалежний оракул — pinned SENS REPL; якщо
його немає в середовищі, scripts/test-zamykannia-svidok.sh друкує
NOT_VERIFIED і називає причину. Ця модель — друга реалізація, а не
заміна авторитету; у звіті вона названа саме так.

Протокол: по одній формі на рядок зі stdin; на кожну — рядок
  OK<TAB><відображення>   або   ERR<TAB><причина>
Ніякого стану між формами: кожна форма обчислюється в порожньому
оточенні, як один виклик EvaluateSource у свідку.
"""
import sys

TRUE_ = object()   # D1:1  (укр «так»)
FALSE_ = object()  # D1:0  (укр «ні»)
NIL_ = object()    # D3:000 (порожній список)


class Closure:
    """Значення D4 FUNCTION: параметри, тіло й ЗАХОПЛЕНЕ оточення.

    Саме наявність третього поля й робить замикання замиканням: без нього
    тіло не має де знайти змінну, якої немає серед аргументів виклику.
    """
    __slots__ = ("params", "body", "env")

    def __init__(self, params, body, env):
        self.params = params
        self.body = body
        self.env = env


class Pair:
    __slots__ = ("head", "tail")

    def __init__(self, head, tail):
        self.head = head
        self.tail = tail


class EvalError(Exception):
    pass


def is_atom(x):
    return isinstance(x, str)


def to_list(x):
    out = []
    while isinstance(x, Pair):
        out.append(x.head)
        x = x.tail
    if x is not NIL_:
        raise EvalError("модель: несподіваний хвіст списку")
    return out


def lookup(name, env):
    """Асоціативний пошук в аліста-оточенні: ((імʼя . значення) ...)."""
    while isinstance(env, Pair):
        b = env.head
        if isinstance(b, Pair) and b.head == name:
            return b.tail
        env = env.tail
    return None


def as_seq(x):
    """Послідовність або як ланцюг D2, або як список Python (після evlis)."""
    if isinstance(x, list):
        return x
    return [] if x is NIL_ else to_list(x)


def pairlis(params, args, env):
    """core1.lisp:190-206 — поєднати-параметри, з двома різними ARITY."""
    pl = as_seq(params)
    al = as_seq(args)
    if not pl and not al:
        return env
    if not pl and al:
        raise EvalError("ARITY: TOO-MANY-ARGUMENTS")
    if pl and not al:
        raise EvalError("ARITY: TOO-FEW-ARGUMENTS")
    if len(pl) != len(al):
        raise EvalError(
            "ARITY: TOO-MANY-ARGUMENTS" if len(pl) < len(al)
            else "ARITY: TOO-FEW-ARGUMENTS")
    # сполучити (сполучити параметр значення) оточення — з голови списку
    for name, value in zip(reversed(pl), reversed(al)):
        env = Pair(Pair(name, value), env)
    return env


def evlis(nodes, env, g):
    """Обчислити кожен аргумент в оточенні виклику (ліворуч-праворуч)."""
    return [eval_form(n, env, g) for n in nodes]


def appq(values):
    """appq лише позначає «вже обчислено» (D3:001 як-є).

    На рівні значень це тотожність; окремої роботи тут немає навмисно:
    модель не повторює фізичне пакування Pascal, а лише наслідок —
    аргумент НЕ обчислюється вдруге як код.
    """
    return values


def apply_closure(cl, args, g):
    env = pairlis(cl.params, args, cl.env)
    return eval_form(cl.body, env, g)


def eval_form(x, env, g):
    if is_atom(x):
        if x == "так":
            return TRUE_
        if x == "ні":
            return FALSE_
        v = lookup(x, env)
        if v is None:
            v = lookup(x, g[0])
        if v is None:
            raise EvalError("unknown native call head")
        return v
    if x is NIL_:
        return NIL_
    if isinstance(x, Pair):
        items = to_list(x)
        if not items:
            return NIL_
        head = items[0]
        args = items[1:]
        if is_atom(head):
            if head == "створити-лямбда-замикання":
                if len(items) != 3:
                    raise EvalError("closure needs parameters and body")
                return Closure(items[1], items[2], env)
            if head == "мітка":
                if len(items) != 3:
                    raise EvalError("мітка: очікую імʼя і тіло")
                name = items[1]
                if not is_atom(name):
                    raise EvalError("мітка: імʼя мусить бути атомом")
                value = eval_form(items[2], env, g)
                # FGlobalEnv у механізмі — поле evaluator, тому звʼязування
                # видиме всій решті ЦЬОГО обчислення, не лише піддереву.
                g[0] = Pair(Pair(name, value), g[0])
                return value
            if head == "сполучити":
                if len(items) != 3:
                    raise EvalError("сполучити: очікую два значення")
                a = eval_form(items[1], env, g)
                b = eval_form(items[2], env, g)
                return Pair(a, b)
            if head == "решта":
                if len(items) != 2:
                    raise EvalError("решта: очікую одне значення")
                v = eval_form(items[1], env, g)
                return v.tail if isinstance(v, Pair) else NIL_
            v = lookup(head, env)
            if v is None:
                v = lookup(head, g[0])
            if isinstance(v, Closure):
                return apply_closure(v, appq(evlis(args, env, g)), g)
            raise EvalError("unknown native call head")
        v = eval_form(head, env, g)
        if not isinstance(v, Closure):
            raise EvalError("обчислена голова не є перевіреним замиканням")
        return apply_closure(v, appq(evlis(args, env, g)), g)
    raise EvalError("модель: невідомий вузол")


def render(v):
    if v is TRUE_:
        return "1"
    if v is FALSE_:
        return "0"
    if v is NIL_:
        return "()"
    if isinstance(v, Pair):
        return "(" + render(v.head) + " . " + render(v.tail) + ")"
    if isinstance(v, Closure):
        return "<замикання>"
    raise EvalError("модель: немає відображення для значення")


# --------------------------------------------------------------------------
# Читач: рівно та поверхня, якою користується свідок.
# --------------------------------------------------------------------------
def tokenize(src):
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
        elif c in "()":
            yield c
            i += 1
        else:
            j = i
            while j < n and src[j] not in " \t\r\n()":
                j += 1
            yield src[i:j]
            i = j


def parse(src):
    stack = [[]]
    for tok in tokenize(src):
        if tok == "(":
            stack.append([])
        elif tok == ")":
            if len(stack) < 2:
                raise EvalError("модель: зайва дужка")
            done = stack.pop()
            stack[-1].append(list_to_pair(done))
        else:
            stack[-1].append(tok)
    if len(stack) != 1:
        raise EvalError("модель: незакрита дужка")
    if len(stack[0]) != 1:
        raise EvalError("модель: очікую одну форму")
    return stack[0][0]


def list_to_pair(items):
    out = NIL_
    for item in reversed(items):
        out = Pair(item, out)
    return out


def main():
    out = sys.stdout
    for line in sys.stdin:
        src = line.rstrip("\n")
        if not src.strip():
            continue
        try:
            value = eval_form(parse(src), NIL_, [NIL_])
            out.write("OK\t" + render(value) + "\n")
        except EvalError as exc:
            out.write("ERR\t" + str(exc) + "\n")
        except Exception as exc:  # модель мусить відмовити, а не впасти
            out.write("ERR\tмодель-збій: " + str(exc) + "\n")
    out.flush()


if __name__ == "__main__":
    main()
