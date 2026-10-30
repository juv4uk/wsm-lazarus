#!/usr/bin/env bash
# G6.212 — ЧИ МОЖНА ВЗАГАЛІ зібрати pinned SENS-оракул у цьому середовищі.
#
# Навіщо: 30.10.2026 агент витратив ~25 хвилин, щоб з'ясувати, що збірка
# оракула впирається в ліміт пам'яті. Цей скрипт дає ту саму відповідь
# за секунду — до, а не після спроби.
#
# Нічого не збирає і не змінює. Лише читає факти середовища.
set -uo pipefail

PIN="1f1bf676eeac605e065035d9dd2adaae807f1788"
NEED_MB=${ORACLE_NEED_MB:-4096}

say() { printf 'ORACLE-FEASIBILITY %s\n' "$*"; }

mem_limit_mb() {
  local f=/sys/fs/cgroup/memory.max
  [ -r "$f" ] || f=/sys/fs/cgroup/memory/memory.limit_in_bytes
  [ -r "$f" ] || return 1
  local v; v=$(cat "$f" 2>/dev/null) || return 1
  [ "$v" = "max" ] && { echo 0; return 0; }
  echo $(( v / 1024 / 1024 ))
}

MEM=$(mem_limit_mb || echo 0)
HAVE_CARGO=no; command -v cargo >/dev/null 2>&1 && HAVE_CARGO=yes
HAVE_RUSTC=no; command -v rustc >/dev/null 2>&1 && HAVE_RUSTC=yes
HAVE_ZIG=no;  command -v zig   >/dev/null 2>&1 && HAVE_ZIG=yes

say "пін=$PIN потрібно_МБ=$NEED_MB ліміт_МБ=$MEM cargo=$HAVE_CARGO rustc=$HAVE_RUSTC zig=$HAVE_ZIG"

VERDICT="можливо"
[ "$MEM" -ne 0 ] && [ "$MEM" -lt "$NEED_MB" ] && VERDICT="заблоковано-памяттю"
[ "$HAVE_CARGO" = no ] && VERDICT="заблоковано-немає-cargo"

case "$VERDICT" in
  заблоковано-памяттю)
    say "ВЕРДИКТ: збірка оракула неможлива тут — ліміт ${MEM} МБ < ${NEED_MB} МБ"
    say "rustc абортує на крейті sens із 'memory allocation of 58720256 bytes failed'"
    say "ORACLE-FEASIBILITY-BLOCKED"
    exit 2 ;;
  заблоковано-немає-cargo)
    say "ВЕРДИКТ: немає cargo — збірка оракула тут неможлива"
    say "ORACLE-FEASIBILITY-BLOCKED"
    exit 2 ;;
  *)
    say "ВЕРДИКТ: середовище придатне для спроби збірки (це не доказ, що збірка вдасться)"
    say "ORACLE-FEASIBILITY-OK"
    exit 0 ;;
esac
