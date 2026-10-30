#!/usr/bin/env bash
# G6.251 — машинний маркер із кирилицею мусить мати {$codepage utf8}.
#
# Навіщо: PR #1032 упав не через SHLD, а через маркер. У лозі було
#   G6.249-SHLD-?????? matrix=64 ...
# — шість `?` там, де мало бути українське слово. FPC без {$codepage utf8}
# псує кирилицю на stdout, а grep -Fxq порівнює байти: маркер ніколи не
# збіжиться, і тест падає з причини, якої в коді не видно.
#
# Перевіряємо РІВНО небезпечну комбінацію: Pascal-файл друкує маркер, що
# містить PASS або FAIL (тобто його порівнюють), і цей маркер містить
# не-ASCII, але директиви {$codepage utf8} немає.
#
# Кирилиця в ПОЯСНЕННЯХ для людини — нормально і не забороняється.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
checked=0
for f in scripts/*.pas scripts/*.lpr src/*.pas src/*.lpr; do
  [ -e "$f" ] || continue
  # чи друкує файл маркер із PASS/FAIL, що містить не-ASCII
  if ! grep -qP "Write(Ln)?\('[^']*[^\x00-\x7F][^']*(PASS|FAIL)" "$f" 2>/dev/null; then
    continue
  fi
  checked=$((checked+1))
  if ! grep -q 'codepage utf8' "$f"; then
    echo "MARKER-CODEPAGE-FAIL $f друкує кириличний маркер PASS/FAIL без {\$codepage utf8} — FPC віддасть '?' і grep не збіжиться" >&2
    fail=1
    continue
  fi
  echo "MARKER-CODEPAGE-OK   $f"
done

if [ "$fail" -ne 0 ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=маркери::Pascal друкує кириличний PASS/FAIL-маркер без {\$codepage utf8}; додайте директиву або зробіть маркер ASCII" >&2
  fi
  exit 1
fi
echo "MARKER-CODEPAGE-PASS перевірено=$checked"
