#!/usr/bin/env bash
# G6.256 — ЧИ ГОТОВЕ ЦЕ СЕРЕДОВИЩЕ ДО РЕАЛЬНОГО ЗАПУСКУ?
#
# Навіщо: пів сеансу я вважав, що в цій пісочниці не можна ні злінкувати,
# ні запустити ELF (`ld.bfd: cannot find libc_nonshared.a`), і тому писав
# лише ті зрізи, які перевіряються компіляцією. Насправді все запускається —
# треба було: (1) покласти fpc у PATH, (2) прогнати scripts/lib-fpc-libs.sh,
# (3) виставити пін підмодуля. Три кроки, які ніде не були зібрані в одному
# місці, коштували дорогих хибних висновків про межі роботи.
#
# Скрипт відповідає на одне питання: чи можна ЗАРАЗ зібрати, злінкувати й
# запустити програму. Коди: 0 — готово, 2 — ні (з переліком того, чого бракує).
set -uo pipefail
cd "$(dirname "$0")/.."

missing=""
note() { printf '  %s\n' "$*"; }

# 1) fpc
if ! command -v fpc >/dev/null 2>&1; then
  for cand in /scratch/work/fpcbin /usr/lib/fpc/3.2.2/bin; do
    if [ -x "$cand/fpc" ]; then PATH="$cand:$PATH"; export PATH; break; fi
  done
fi
if command -v fpc >/dev/null 2>&1; then
  note "fpc: $(command -v fpc) ($(fpc -iV 2>/dev/null))"
else
  missing="$missing fpc"
  note "fpc: НЕМА"
fi

# 2) бібліотеки лінкування
if [ -f scripts/lib-fpc-libs.sh ]; then
  libout=$(bash scripts/lib-fpc-libs.sh 2>&1 | tail -1)
  note "libs: ${libout:-без відповіді}"
  case "$libout" in
    *FAIL*) missing="$missing libs" ;;
  esac
else
  note "libs: немає scripts/lib-fpc-libs.sh"
fi

# 3) пін підмодуля
pin=$(git ls-tree HEAD external/sens 2>/dev/null | awk '{print $3}')
have=$(git -C external/sens rev-parse HEAD 2>/dev/null)
if [ -n "$pin" ] && [ "$pin" = "$have" ]; then
  note "пін: ${pin:0:12} (збігається)"
else
  note "пін: очікували ${pin:0:12}, маємо ${have:0:12} — виставте: (cd external/sens && git checkout $pin)"
  missing="$missing pin"
fi

# 4) реальна збірка + лінк + запуск
if command -v fpc >/dev/null 2>&1; then
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  printf 'program t;\nbegin WriteLn(2+3); end.\n' > "$work/t.pas"
  if fpc -O1 "$work/t.pas" -o"$work/t" >/dev/null 2>&1; then
    if got=$("$work/t" 2>/dev/null) && [ "$got" = "5" ]; then
      note "запуск: так (2+3 → 5)"
    else
      note "запуск: збірка є, але програма не дала 5"
      missing="$missing run"
    fi
  else
    note "збірка: fpc є, але лінк не вдався"
    missing="$missing link"
  fi
fi

if [ -n "$missing" ]; then
  echo "LOCAL-TOOLCHAIN-НЕГОТОВО бракує:$missing" >&2
  exit 2
fi
echo "LOCAL-TOOLCHAIN-ГОТОВО збірка=так лінк=так запуск=так пін=так"
