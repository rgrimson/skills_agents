#!/usr/bin/env bash
# Arma los lotes de tiles: un archivo de texto por lote, con una ruta por línea relativa a entrada/.
# Cada lote lo procesa una tarea del job array (un nodo completo de Serafín).
# Se corre en la cabecera, desde la carpeta del proyecto:
#
#   bash scripts/armar_lotes.sh 40                    # 40 tiles por lote, archivos .las/.laz
#   PATRON='*.tif' bash scripts/armar_lotes.sh 200    # otro tipo de archivo
#   bash scripts/armar_lotes.sh 40 -f                 # rehacer lotes existentes
#
# Ver references/cpu-tiles.md, "Dimensionar", para elegir cuántos tiles por lote.
set -euo pipefail

N=${1:?uso: armar_lotes.sh TILES_POR_LOTE [-f]}
FORZAR=${2:-}
[ -d entrada ] || { echo "no hay entrada/ (correr desde la carpeta del proyecto)" >&2; exit 1; }

if compgen -G "lotes/lote_*.txt" >/dev/null; then
    if [ "$FORZAR" != "-f" ]; then
        echo "ya hay lotes en lotes/. Si los tiles cambiaron, repetir con -f (los tiles terminados no se rehacen igual)." >&2
        exit 1
    fi
    rm -f lotes/lote_*.txt
fi
mkdir -p lotes

if [ -n "${PATRON:-}" ]; then
    find -L entrada -type f -iname "$PATRON" -printf '%P\n'
else
    find -L entrada -type f \( -iname '*.las' -o -iname '*.laz' \) -printf '%P\n'
fi | sort > lotes/todos.txt

TOTAL=$(wc -l < lotes/todos.txt)
[ "$TOTAL" -gt 0 ] || { echo "no encontré tiles en entrada/" >&2; exit 1; }

# Los nombres de salida se toman del nombre del archivo sin extensión: tienen que ser únicos.
DUP=$(sed 's#.*/##; s/\.[^.]*$//' lotes/todos.txt | sort | uniq -d | head -5)
[ -z "$DUP" ] || { echo "hay nombres de tile repetidos en subcarpetas distintas, por ejemplo: $DUP" >&2; exit 1; }

split -l "$N" -d -a 4 --numeric-suffixes=1 --additional-suffix=.txt lotes/todos.txt lotes/lote_
NLOTES=$(compgen -G "lotes/lote_*.txt" | wc -l)
echo "$TOTAL tiles en $NLOTES lotes de hasta $N."
echo "Encolar con:"
echo "  Helvetios:  sbatch --array=1-$NLOTES%4 -c 36 --mem=0 scripts/lote_tiles.sbatch"
echo "  Serafín:    sbatch --array=1-$NLOTES%4 scripts/lote_tiles.sbatch"
