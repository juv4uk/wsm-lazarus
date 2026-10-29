#!/usr/bin/env bash
# Нативний host-знімач RAPL; семантики SENS і фізичних джоулів CI не вигадує.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo "RAPL-БЛОК: потрібен FPC" >&2; exit 127; }
UNITS="$ROOT/build/m0.2/rapl-units"
BINS="$ROOT/build/m0.2/bin"
mkdir -p "$UNITS" "$BINS"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$UNITS" -FE"$BINS" -osensrapl "$ROOT/scripts/energy/sensrapl.lpr"
BIN="$BINS/sensrapl"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sys/intel-rapl:0/intel-rapl:0:0"
printf 'package-0\n' > "$TMP/sys/intel-rapl:0/name"
printf '99999990\n' > "$TMP/sys/intel-rapl:0/energy_uj"
printf '100000000\n' > "$TMP/sys/intel-rapl:0/max_energy_range_uj"
printf 'core\n' > "$TMP/sys/intel-rapl:0/intel-rapl:0:0/name"
printf '4\n' > "$TMP/sys/intel-rapl:0/intel-rapl:0:0/energy_uj"
printf '500000000\n' > "$TMP/sys/intel-rapl:0/intel-rapl:0:0/max_energy_range_uj"
"$BIN" --знімок "$TMP/sys" > "$TMP/до.tsv"
[[ "$(wc -l < "$TMP/до.tsv")" -eq 3 ]]
grep -Fqx $'intel-rapl:0\tpackage-0\t99999990\t100000000' "$TMP/до.tsv"
grep -Fqx $'intel-rapl:0/intel-rapl:0:0\tcore\t4\t500000000' "$TMP/до.tsv"
printf '20\n' > "$TMP/sys/intel-rapl:0/energy_uj"
printf '25\n' > "$TMP/sys/intel-rapl:0/intel-rapl:0:0/energy_uj"
"$BIN" --знімок "$TMP/sys" > "$TMP/після.tsv"
"$BIN" --різниця "$TMP/до.tsv" "$TMP/після.tsv" 50000 1000 > "$TMP/різниця.tsv"
[[ "$(wc -l < "$TMP/різниця.tsv")" -eq 3 ]]
grep -Fqx $'intel-rapl:0\tpackage-0\t99999990\t20\t100000000\t30' "$TMP/різниця.tsv"
grep -Fqx $'intel-rapl:0/intel-rapl:0:0\tcore\t4\t25\t500000000\t21' "$TMP/різниця.tsv"

checks=4
reject() {
  local name="$1"
  shift
  if "$BIN" "$@" > "$TMP/відмова.stdout" 2> "$TMP/відмова.stderr"; then
    echo "RAPL-ПОМИЛКА: прийнято $name" >&2
    exit 1
  fi
  [[ ! -s "$TMP/відмова.stdout" ]] || {
    echo "RAPL-ПОМИЛКА: частковий stdout після $name" >&2; exit 1;
  }
  [[ -s "$TMP/відмова.stderr" ]] || {
    echo "RAPL-ПОМИЛКА: немає діагностики $name" >&2; exit 1;
  }
  checks=$((checks+1))
}

reject "неіснуючий каталог" --знімок "$TMP/немає"
grep -Fq ENERGY_NOT_MEASURED "$TMP/відмова.stderr"
reject "без RAPL" --знімок "$TMP"
grep -Fq ENERGY_NOT_MEASURED "$TMP/відмова.stderr"
reject "прихований додатковий оберт" --різниця "$TMP/до.tsv" "$TMP/після.tsv" 100000 1000
reject "нульовий час" --різниця "$TMP/до.tsv" "$TMP/після.tsv" 0 1000
reject "нульова потужність" --різниця "$TMP/до.tsv" "$TMP/після.tsv" 50000 0
reject "від'ємна потужність" --різниця "$TMP/до.tsv" "$TMP/після.tsv" 50000 -1
reject "невідомий параметр" --помилка "$TMP/sys"
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
sed -i 's/500000000/500000001/' "$TMP/зміна.tsv"
reject "підміна діапазону" --різниця "$TMP/до.tsv" "$TMP/зміна.tsv" 50000 1000
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
sed -i 's/package-0/package-1/' "$TMP/зміна.tsv"
reject "підміна назви" --різниця "$TMP/до.tsv" "$TMP/зміна.tsv" 50000 1000
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
sed -i 's/\t20\t/\t100000000\t/' "$TMP/зміна.tsv"
reject "лічильник за межею" --різниця "$TMP/до.tsv" "$TMP/зміна.tsv" 50000 1000
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
sed -i '2d' "$TMP/зміна.tsv"
reject "відсутня зона" --різниця "$TMP/до.tsv" "$TMP/зміна.tsv" 50000 1000
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
sed -n '2p' "$TMP/зміна.tsv" >> "$TMP/зміна.tsv"
reject "дубль зони" --різниця "$TMP/до.tsv" "$TMP/зміна.tsv" 50000 1000
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
{ head -1 "$TMP/зміна.tsv"; tail -n +2 "$TMP/зміна.tsv" | tac; } > "$TMP/переставлено.tsv"
reject "неканонічний порядок" --різниця "$TMP/до.tsv" "$TMP/переставлено.tsv" 50000 1000
cp "$TMP/після.tsv" "$TMP/зміна.tsv"
sed -i '2s/20/2x/' "$TMP/зміна.tsv"
reject "нецифровий датчик" --різниця "$TMP/до.tsv" "$TMP/зміна.tsv" 50000 1000
printf 'bad\n' > "$TMP/sys/intel-rapl:0/energy_uj"
reject "поганий фізичний датчик" --знімок "$TMP/sys"
rm "$TMP/sys/intel-rapl:0/energy_uj"
reject "відсутній фізичний датчик" --знімок "$TMP/sys"

printf 'RAPL-ФІЗИЧНИЙ-HOST-OK checks=%s wrap=30 nested=distinct energy=ENERGY_NOT_MEASURED\n' "$checks"
