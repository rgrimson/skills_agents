#!/usr/bin/env bash
# Resumen del avance de la corrida, en la cabecera, desde la carpeta del proyecto. Sólo lee archivos.
#
#   bash scripts/estado.sh              # totales, lotes incompletos y últimos fallos
#   bash scripts/estado.sh fallos       # cada tile fallido con el final de su log
#
# Los tiles fallidos se reintentan solos al relanzar su lote (sólo se saltean los que están en estado/ok/).
set -euo pipefail
[ -f lotes/todos.txt ] || { echo "no hay lotes/todos.txt (correr desde la carpeta del proyecto)" >&2; exit 1; }
mkdir -p estado/ok estado/fallo

nombre() { local n; n=$(basename "$1"); echo "${n%.*}"; }

case "${1:-}" in
fallos)
    for f in estado/fallo/*; do
        [ -e "$f" ] || { echo "no hay fallos"; exit 0; }
        n=$(basename "$f")
        echo "== $n ($(cat "$f"))"
        tail -n 8 "logs/tiles/$n.log" 2>/dev/null | sed 's/^/   /'
    done
    ;;
*)
    TOT=$(wc -l < lotes/todos.txt)
    OK=$(find estado/ok -type f | wc -l)
    FA=$(find estado/fallo -type f | wc -l)
    echo "tiles: $TOT  ok: $OK  fallidos: $FA  pendientes: $((TOT - OK - FA))"
    if [ "$OK" -gt 0 ]; then
        cat estado/ok/* | sort -n | awk '{a[NR]=$1; s+=$1} END {printf "segundos por tile: mediana %d, máximo %d, total %.1f h-core\n", a[int((NR+1)/2)], a[NR], s/3600}'
    fi
    INCOMPLETOS=()
    for l in lotes/lote_*.txt; do
        i=$(basename "$l" .txt); i=$((10#${i#lote_}))
        while IFS= read -r rel; do
            [ -e "estado/ok/$(nombre "$rel")" ] || { INCOMPLETOS+=("$i"); break; }
        done < "$l"
    done
    if [ "${#INCOMPLETOS[@]}" -gt 0 ]; then
        LISTA=$(IFS=,; echo "${INCOMPLETOS[*]}")
        echo "lotes incompletos: $LISTA"
        echo "relanzar con:  sbatch --array=$LISTA%4 scripts/lote_tiles.sbatch"
    else
        echo "todos los lotes completos"
    fi
    if [ "$FA" -gt 0 ]; then
        echo "fallos (ver detalle con: bash scripts/estado.sh fallos):"
        ls estado/fallo | sed -n '1,10s/^/   /p'
    fi
    ;;
esac
