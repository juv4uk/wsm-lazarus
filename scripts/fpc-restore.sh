#!/usr/bin/env bash
# G6.201 (задача #805) — одне встановлення fp-compiler на ніч, а не 248.
#
# Що робить скрипт:
#   * теплий кеш  — розпаковує готовий образ FPC (~/.cache/fpc-root/fpc-root.tar)
#                   у / і НЕ викликає apt-get взагалі;
#   * холодний кеш — ставить fp-compiler через apt рівно один раз і знімає
#                   з нього образ для наступних прогонів.
#
# Кеш спільний для всіх workflow (ключ fpc-root-$runner.os-24.04-3.2.2-v1),
# тому за ніч apt викликається щонайбільше один раз на весь пакет, а не на
# кожен workflow.
#
# Скрипт НІКОЛИ не прибирає перевірку: якщо кеш відсутній або зіпсований —
# виконується звичайний apt-get install, і перевірка далі йде тим самим шляхом.
# Якщо не вдається ні те, ні те — скрипт падає з ненульовим кодом, щоб збій
# було видно, а не замовчано.
#
# Кожен прогін пише у $GITHUB_STEP_SUMMARY рядок FPC-INSTALL: cache|apt,
# тому кількість справжніх apt-встановлень видно з логів, а не з припущень.
set -euo pipefail

CACHE_DIR="${FPC_CACHE_DIR:-$HOME/.cache/fpc-root}"
TAR="$CACHE_DIR/fpc-root.tar"
MARKER="$CACHE_DIR/.ready"
WANTED_PREFIX="${FPC_VERSION_PREFIX:-3.2}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

say() { echo "$*"; }
summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$*" >> "$GITHUB_STEP_SUMMARY"
  fi
}

install_with_apt() {
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends fp-compiler git
}

# Знімок усіх файлів, що їх поклали пакети fp-*.
snapshot() {
  mkdir -p "$CACHE_DIR"
  local owned
  owned=$(mktemp)
  dpkg -l 2>/dev/null | awk '$1 == "ii" { n = $2; sub(/:.*/, "", n); if (n ~ /^fp-/) print n }' > "$owned.pkg"
  if [ ! -s "$owned.pkg" ]; then
    rm -f "$owned" "$owned.pkg"
    return 1
  fi
  # shellcheck disable=SC2046
  dpkg -L $(cat "$owned.pkg") 2>/dev/null \
    | grep -E '^/(usr|etc)/' | sort -u > "$owned"
  rm -f "$owned.pkg"
  if [ ! -s "$owned" ]; then
    rm -f "$owned"
    return 1
  fi
  # dpkg -L перелічує також директорії. Типова рекурсія tar розростає
  # кеш на все /usr і може забрати 10+ хвилин та чужі пакети.
  # --no-recursion пакує ТІЛЬКИ явно перелічені dpkg paths.
  # Borrowed: $owned (строковий список шляхів); owned: TAR та MARKER.
  # 1. Чому списку dpkg недостатньо без --no-recursion?
  # 2. Чому marker не можна залишати після невдалого tar?
  # 3. Чому помилка кешування не має маскувати невдале встановлення FPC?
  # 4. Хто видаляє частковий архів після помилки?
  if ! sudo tar -C / --no-recursion -cpf "$TAR" -T "$owned"; then
    rm -f "$TAR" "$MARKER" "$owned"
    return 1
  fi
  rm -f "$owned"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER"
}

restore_from_cache() {
  # Явний return: інакше статус функції визначав би ldconfig і помилка
  # розпакування була б замаскована.
  sudo tar -C / -xpf "$TAR" || return 1
  sudo ldconfig 2>/dev/null || true
  return 0
}

fpc_ok() {
  command -v fpc >/dev/null 2>&1 &&
    fpc -iV 2>/dev/null | grep -q "^${WANTED_PREFIX}"
}

# G6.231 — шим бібліотек лінкування FPC (libc.so/libdl.so).
# У мінімальному контейнері немає development-симлінків glibc, і ld.bfd
# валить компіляцію з «cannot find -lc». Хелпер створює шим і дописує
# -Fl<шим> у ~/.fpc.cfg, який читає кожен виклик fpc.
#
# НЕФАТАЛЬНО ЗА ЗАДУМОМ. Цей скрипт ставить FPC, і на ньому тримаються
# 78 workflow. Збій шиму — це привід для попередження в лозі, а не для
# падіння встановлення: краще поставити FPC без шиму, ніж не поставити
# його взагалі. Саме тому виклик нижче завжди йде з `|| true`, а сама
# функція повертає 0 за будь-якого результату.
ensure_fpc_libs() {
  local helper="$SCRIPT_DIR/lib-fpc-libs.sh"
  if [ ! -f "$helper" ]; then
    say "FPC-LIBS-WARN: хелпер відсутній path=$helper (нефатально)"
    return 0
  fi
  if bash "$helper"; then
    summary "- FPC-LIBS: шим бібліотек лінкування застосовано"
  else
    say "FPC-LIBS-WARN: шим не застосовано — FPC встановлено, лінкування може впасти на -lc/-ldl (нефатально)"
    summary "- FPC-LIBS-WARN: шим не застосовано (нефатально)"
  fi
  return 0
}

if [ -f "$TAR" ] && [ -f "$MARKER" ] && command -v git >/dev/null 2>&1; then
  if restore_from_cache && fpc_ok; then
    say "FPC-INSTALL: cache (apt-get install не викликався)"
    summary "- FPC-INSTALL: cache — apt-get install не викликався"
    fpc -iV
    ensure_fpc_libs || true
    exit 0
  fi
  say "FPC-INSTALL: cache пошкоджений — повертаюсь до apt"
  rm -f "$TAR" "$MARKER"
fi

say "FPC-INSTALL: apt (холодний кеш — одне встановлення на весь нічний пакет)"
install_with_apt
if ! fpc_ok; then
  say "FPC-INSTALL-FAIL: fp-compiler не встановився або версія не ${WANTED_PREFIX}.x"
  exit 1
fi
if snapshot; then
  say "FPC-INSTALL: образ знято у $TAR"
else
  say "FPC-INSTALL-WARN: образ зняти не вдалось — наступний прогін знову поставить через apt"
fi
summary "- FPC-INSTALL: apt — холодний кеш, одне встановлення на нічний пакет"
fpc -iV
ensure_fpc_libs || true
