#!/usr/bin/env bash
# G6.231 — СПІЛЬНИЙ хелпер бібліотек лінкування для FPC-тестів.
#
# НАВІЩО. У мінімальному середовищі (контейнер без libc6-dev) є лише
# рантайм-файли glibc — libc.so.6 і libdl.so.2 — але немає development-
# симлінків libc.so / libdl.so. Тоді `ld.bfd` каже `cannot find -lc`
# (або `cannot find -ldl`), і падають ті тести, чиї програми тягнуть
# `{$linklib c}` (напр. через BaseUnix) або `{$linklib dl}` (через heaptrc).
# Це ВІДМОВА СЕРЕДОВИЩА, а не дефект семантики тесту.
#
# ЩО РОБИТЬ. Хелпер — єдине місце, де ця відмова усувається:
#   1. перевіряє, чи `-lc` / `-ldl` уже розв'язуються штатно;
#   2. якщо ні — створює каталог-шим із симлінками libc.so -> libc.so.6
#      та libdl.so -> libdl.so.2 (саме те, що дав би пакет libc6-dev);
#   3. дописує `-Fl<шим>` у користувацький конфіг FPC (~/.fpc.cfg), який
#      читає КОЖЕН виклик `fpc`. Через це виправлення діє на всі тести
#      одразу, без правки жодного тесту поштучно.
#
# ІДЕМПОТЕНТНІСТЬ. Якщо libc.so/libdl.so уже є (повноцінний libc6-dev або
# попередній прогін хелпера) — хелпер НІЧОГО не створює й не переписує,
# лише друкує state=native|shim. Блок у ~/.fpc.cfg обмежений маркерами,
# тому повторний прогін не дублює рядків. Середовище з робочим libc.so
# хелпер не ламає: він там не втручається взагалі.
#
# ЧОГО ХЕЛПЕР НЕ РОБИТЬ. Він не вимикає перевірки, не змінює прапорці
# тестів і не підміняє відсутню бібліотеку заглушкою. Якщо немає навіть
# libc.so.6 / libdl.so.2 — це FPC-LIBS-FAIL з точним переліком відсутнього,
# і хелпер завершується ненульовим кодом.
#
# ВИКОРИСТАННЯ.
#   bash scripts/lib-fpc-libs.sh            # застосувати (шим + ~/.fpc.cfg)
#   bash scripts/lib-fpc-libs.sh --flags    # лише надрукувати -Fl<шим>
#   bash scripts/lib-fpc-libs.sh --check    # нічого не створювати; 0 = лінк ок
#   . scripts/lib-fpc-libs.sh && fpc_ensure_lib_flags
#
# ЗМІННІ.
#   FPC_LIBSHIM_DIR   каталог шиму (типово ~/.cache/fpc-libshim)
#   FPC_LIBS_CFG      файл користувацького конфігу (типово ~/.fpc.cfg)
#   FPC_LIBS_CFG=0    не чіпати конфіг, лише створити шим і надрукувати -Fl

# Коли файл підключають через `.`/`source`, прапорці оболонки не нав'язуємо
# викликачу — інакше зламали б `set +e` у тестах, що свідомо ловлять код.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
fi

FPC_LIBS_CFG_MARK_BEGIN='# >>> lib-fpc-libs.sh (G6.231) >>>'
FPC_LIBS_CFG_MARK_END='# <<< lib-fpc-libs.sh (G6.231) <<<'

# Каталоги, де glibc тримає і рантайм, і development-симлінки.
_fpc_libs_dirs() {
  printf '%s\n' \
    /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu \
    /usr/lib64 /lib64 /usr/lib /lib /usr/local/lib
}

_fpc_libs_shim_dir() {
  printf '%s\n' "${FPC_LIBSHIM_DIR:-$HOME/.cache/fpc-libshim}"
}

# fpc_link_lib_present <c|dl> — чи є вже придатний для `-l<name>` файл.
# Шукаємо lib<name>.so (симлінк або справжній файл) та lib<name>.a.
fpc_link_lib_present() {
  local name="$1" d
  d=$(_fpc_libs_shim_dir)
  for dir in "$d" $(_fpc_libs_dirs); do
    [ -n "$dir" ] || continue
    if [ -e "$dir/lib$name.so" ] || [ -e "$dir/lib$name.a" ]; then
      return 0
    fi
  done
  return 1
}

# fpc_lib_soname <c|dl> — знайти фактичний рантайм-файл, на який зробимо симлінк.
fpc_lib_soname() {
  local name="$1" dir cand
  case "$name" in
    c)  cand="libc.so.6" ;;
    dl) cand="libdl.so.2" ;;
    *)  return 1 ;;
  esac
  for dir in $(_fpc_libs_dirs); do
    if [ -e "$dir/$cand" ]; then
      printf '%s\n' "$dir/$cand"
      return 0
    fi
  done
  return 1
}

# fpc_write_user_cfg <shimdir> — ідемпотентно тримати `-Fl<shimdir>` у конфігу FPC.
fpc_write_user_cfg() {
  local shim="$1"
  local cfg="${FPC_LIBS_CFG:-$HOME/.fpc.cfg}"
  local line="-Fl$shim"
  local tmp

  if [ "${FPC_LIBS_CFG:-}" = "0" ]; then
    return 0
  fi

  # Уже є рівно цей рядок у нашому блоці — нічого не переписуємо.
  if [ -f "$cfg" ] && grep -Fxq -- "$line" "$cfg"; then
    return 0
  fi

  mkdir -p "$(dirname "$cfg")"
  tmp=$(mktemp)
  if [ -f "$cfg" ]; then
    # Прибираємо старий блок маркерів (могло лишитись від іншого шиму),
    # решту вмісту користувача зберігаємо як є.
    awk -v b="$FPC_LIBS_CFG_MARK_BEGIN" -v e="$FPC_LIBS_CFG_MARK_END" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip   { print }
    ' "$cfg" > "$tmp"
  fi
  {
    cat "$tmp"
    printf '%s\n' "$FPC_LIBS_CFG_MARK_BEGIN"
    printf '%s\n' "$line"
    printf '%s\n' "$FPC_LIBS_CFG_MARK_END"
  } > "$cfg.new"
  mv "$cfg.new" "$cfg"
  rm -f "$tmp"
}

# fpc_ensure_lib_flags — головна дія. Друкує `-Fl<dir>` (або нічого),
# створюючи шим лише тоді, коли він справді потрібен.
# Повертає 1 з FPC-LIBS-FAIL у stderr, якщо бракує навіть рантайм-файлів.
fpc_ensure_lib_flags() {
  local shim need="" name soname missing=""

  shim=$(_fpc_libs_shim_dir)

  for name in c dl; do
    if ! fpc_link_lib_present "$name"; then
      need="$need $name"
    fi
  done

  # Усе на місці — жодних змін у середовищі (ідемпотентність).
  if [ -z "$need" ]; then
    return 0
  fi

  mkdir -p "$shim" || {
    printf 'FPC-LIBS-FAIL cannot-create-shim dir=%s\n' "$shim" >&2
    return 1
  }

  for name in $need; do
    if soname=$(fpc_lib_soname "$name"); then
      # -n: не розіменовувати наявний симлінк; -f: перезаписати свій же.
      ln -sfn "$soname" "$shim/lib$name.so" || {
        printf 'FPC-LIBS-FAIL cannot-link %s -> %s\n' "$shim/lib$name.so" "$soname" >&2
        return 1
      }
    else
      missing="$missing lib$name.so"
    fi
  done

  if [ -n "$missing" ]; then
    # Немає навіть рантайм-файлу: це справжній блокер, а не привід вимикати тест.
    printf 'FPC-LIBS-FAIL missing=%s reason=no-runtime-glibc\n' "${missing# }" >&2
    return 1
  fi

  fpc_write_user_cfg "$shim" || {
    printf 'FPC-LIBS-FAIL cannot-write-cfg file=%s\n' "${FPC_LIBS_CFG:-$HOME/.fpc.cfg}" >&2
    return 1
  }

  printf -- '-Fl%s\n' "$shim"
  return 0
}

# --- Виконання як команди -----------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --check)
      # Лише діагностика: НІЧОГО не створює і не переписує.
      missing=""
      for name in c dl; do
        fpc_link_lib_present "$name" || missing="$missing lib$name.so"
      done
      if [ -n "$missing" ]; then
        printf 'FPC-LIBS-FAIL missing=%s reason=no-dev-symlink\n' \
          "${missing# }" >&2
        exit 1
      fi
      printf 'FPC-LIBS-OK state=native flags=\n'
      ;;
    --flags)
      if ! fpc_ensure_lib_flags; then
        exit 1
      fi
      ;;
    "")
      if ! flags=$(fpc_ensure_lib_flags); then
        exit 1
      fi
      if [ -n "$flags" ]; then
        printf 'FPC-LIBS-OK state=shim dir=%s flags=%s\n' \
          "$(_fpc_libs_shim_dir)" "$flags"
      else
        printf 'FPC-LIBS-OK state=native flags=\n'
      fi
      ;;
    *)
      printf 'вжиток: %s [--check|--flags]\n' "$0" >&2
      exit 2
      ;;
  esac
fi
