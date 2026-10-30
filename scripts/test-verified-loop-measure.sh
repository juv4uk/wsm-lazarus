#!/usr/bin/env bash
# G6.245 — регресія режиму вимірювання, без важкої компіляції на кожен PR.
# Ізольований host-імітаційний FPC тут перевіряє лише shell-керування:
# реальні FPC/SENS/ELF і джоулі цей тест НЕ засвідчує.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# Вузький PATH приховує rustc/gcc: жодних дорогих збірок або фальшивих
# енергетичних даних. Залишаємо рівно потрібні host-утиліти.
for tool in bash dirname mktemp mkdir rm date grep cut sed git cat chmod; do
  command -v "$tool" >/dev/null || { echo "LOOP-MEASURE-БЛОК: $tool" >&2; exit 127; }
  ln -s "$(command -v "$tool")" "$TMP/bin/$tool"
done

cat >"$TMP/bin/fpc" <<'FPC'
#!/usr/bin/env bash
set -euo pipefail
out_dir=''
out_name=''
for arg in "$@"; do
  case "$arg" in
    -FE*) out_dir="${arg#-FE}" ;;
    -o*) out_name="${arg#-o}" ;;
  esac
done
[[ -n "$out_dir" && -n "$out_name" ]] || exit 41
mkdir -p "$out_dir"
cat >"$out_dir/$out_name" <<'EXE'
#!/usr/bin/env bash
n="${1:-1000000}"
k="${2:-1}"
if [[ "${MOCK_BROKEN:-0}" = 1 ]]; then exit 0; fi
exit $(( ((n % 256) * (k % 256)) % 256 ))
EXE
chmod +x "$out_dir/$out_name"
FPC
chmod +x "$TMP/bin/fpc"

need() {
  if ! grep -Fq "$1" "$2"; then
    echo "LOOP-MEASURE-ПРОВАЛ: не знайдено [$1] у [$2]" >&2
    cat "$2" >&2
    exit 1
  fi
}

# 1) Значення 3 — коректний ненульовий exit, включно з двома замірами.
env PATH="$TMP/bin" LOOP_NS=3 LOOP_K=1 LOOP_REPEATS=2 \
  bash "$ROOT/scripts/run-loop-twins.sh" --measure >"$TMP/nonzero.log" 2>&1
need 'N=3 K=1 оракул=3' "$TMP/nonzero.log"
need 'N=3 loop-pas мін.=' "$TMP/nonzero.log"
need 'LOOP-TWINS-PASS' "$TMP/nonzero.log"

# 2) Зберігаємо стару форму API з аргументом шляху; нульовий результат.
env PATH="$TMP/bin" LOOP_NS=256 LOOP_K=1 LOOP_REPEATS=1 \
  bash "$ROOT/scripts/run-loop-twins.sh" "$ROOT" --measure >"$TMP/zero.log" 2>&1
need 'N=256 K=1 оракул=0' "$TMP/zero.log"
need 'LOOP-TWINS-PASS' "$TMP/zero.log"

# 3) Неправильна відповідь є помилкою, хоч сам процес повернув код 0.
if env PATH="$TMP/bin" LOOP_NS=3 LOOP_K=1 LOOP_REPEATS=2 MOCK_BROKEN=1 \
  bash "$ROOT/scripts/run-loop-twins.sh" --measure >"$TMP/bad.log" 2>&1; then
  echo 'LOOP-MEASURE-ПРОВАЛ: хибну відповідь прийнято' >&2; exit 1
fi
need 'FPC loop(N=3)=0, оракул 3' "$TMP/bad.log"
need 'LOOP-TWINS-FAIL' "$TMP/bad.log"

# 4–5) Некоректну кількість повторів та параметри відхиляємо ДО збірки.
if env PATH="$TMP/bin" LOOP_REPEATS=0 \
  bash "$ROOT/scripts/run-loop-twins.sh" --measure >"$TMP/repeats.log" 2>&1; then
  echo 'LOOP-MEASURE-ПРОВАЛ: 0 повторів прийнято' >&2; exit 1
fi
need 'LOOP_REPEATS має бути додатним' "$TMP/repeats.log"
if env PATH="$TMP/bin" bash "$ROOT/scripts/run-loop-twins.sh" --невідомо \
  >"$TMP/argument.log" 2>&1; then
  echo 'LOOP-MEASURE-ПРОВАЛ: невідомий параметр прийнято' >&2; exit 1
fi
need 'невідомий параметр --невідомо' "$TMP/argument.log"

# Питання для перевірки: чому exit 3 тут успіх? Чому фальшивий FPC
# не є доказом SENS? Чому вимір охоплює старт процесу? Де міряти джоулі?
echo 'VERIFIED-LOOP-MEASURE-PASS cases=5 real-fpc=NOT-CHECKED energy=NOT-MEASURED'
