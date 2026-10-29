#!/usr/bin/env python3
"""Поверхня Core1: що саме він визначає і на чому стоїть.

Навіщо: агент мусить знати, що Core1 уже дає, ПЕРЕД тим як писати нове.
96 визначень у external/sens/lib/core1.lisp — це і є та поверхня.

Друге, важливіше: скрипт показує, на яких D3-примітивах тримається
кожне визначення. Якщо воно вживає лише допущені — воно виконуване
наявним evaluator-ом. Якщо вживає «функція» або «мітка» — для нього
потрібен механізм, якого evaluator ще не має (#490).
"""
import collections, pathlib, re, sys

D3_ALLOWED = {"як-є", "атом?", "решта", "перше", "тотожне?", "за-умовою", "сполучити"}
NEEDS_MECHANISM = {"функція", "мітка"}


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    src = root / "external" / "sens" / "lib" / "core1.lisp"
    if not src.is_file():
        print("немає core1.lisp — ініціалізуй external/sens", file=sys.stderr)
        return 2
    text = src.read_text(encoding="utf-8")
    lines = text.splitlines()

    defs = {}
    for number, line in enumerate(lines, 1):
        m = re.search(r"\(\s*визначити\s+\(?\s*([^\s()]+)", line)
        if m and m.group(1) not in defs:
            defs[m.group(1)] = number

    # Тіло кожного визначення — до наступного визначення.
    order = sorted(defs.items(), key=lambda kv: kv[1])
    report = []
    for i, (name, start) in enumerate(order):
        end = order[i + 1][1] - 1 if i + 1 < len(order) else len(lines)
        body = "\n".join(lines[start - 1:end])
        tokens = set(re.findall(r"[^\s()\[\]]+", body))
        used = sorted(tokens & D3_ALLOWED)
        needs = sorted(tokens & NEEDS_MECHANISM)
        report.append((name, start, used, needs))

    needs_count = sum(1 for _, _, _, n in report if n)
    out = root / "knowledge" / "core1-poverhnia.md"
    out.parent.mkdir(exist_ok=True)
    doc = [
        "# Поверхня Core1",
        "",
        f"Джерело: `external/sens/lib/core1.lisp` · **{len(report)} визначень**.",
        "",
        "## На чому стоїть Core1",
        "",
        f"- **{len(report) - needs_count}** визначень уживають лише допущені D3-примітиви.",
        f"- **{needs_count}** уживають `функція` або `мітка` — без них evaluator їх не виконає (#490).",
        "",
        "Допущені D3 (за `lib/domains/d3.lisp`): "
        + " · ".join(f"`{x}`" for x in sorted(D3_ALLOWED)),
        "",
        "## Перелік",
        "",
        "| # | функція | рядок | потребує механізму |",
        "|---|---|---|---|",
    ]
    for i, (name, start, _used, needs) in enumerate(report, 1):
        doc.append(f"| {i} | `{name}` | {start} | {'так: ' + ', '.join(needs) if needs else '—'} |")
    out.write_text("\n".join(doc) + "\n", encoding="utf-8")

    print(f"визначень: {len(report)}")
    print(f"  лише D3: {len(report) - needs_count}")
    print(f"  потребують функція/мітка: {needs_count}")
    print(f"  -> {out.relative_to(root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
