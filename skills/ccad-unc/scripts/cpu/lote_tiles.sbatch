#!/bin/bash
# Procesa un lote de tiles en un nodo completo. Una tarea del array = un lote = un nodo.
# Los #SBATCH de abajo son para Serafín (64 cores). Encolar desde la carpeta del proyecto
# (la cantidad de lotes la imprime armar_lotes.sh):
#
#   sbatch --array=1-NLOTES%4 scripts/lote_tiles.sbatch                      # Serafín
#   sbatch --array=1-NLOTES%4 -c 36 --mem=0 scripts/lote_tiles.sbatch        # Helvetios (36 cores, toda la RAM)
#   sbatch --array=1-NLOTES%4 --export=ALL,P=32 scripts/lote_tiles.sbatch     # menos procesos por nodo
#   sbatch --array=7,12 scripts/lote_tiles.sbatch                               # relanzar lotes puntuales
#
# %4 = como máximo 4 nodos a la vez: deja lugar a otros usuarios y alcanza para avanzar rápido.
# Relanzar un lote es seguro: los tiles terminados (estado/ok/) se saltean.
#
#SBATCH --job-name=tiles
#SBATCH --partition=short              # short: hasta 1 h, arranca rápido. Larga: multi (Serafín), batch (Helvetios)
#SBATCH --time=0-01:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64             # Serafín; en Helvetios pasar -c 36 --mem=0 al encolar
#SBATCH --exclusive
#SBATCH --output=logs/%x-%A_%a.out     # logs/ tiene que existir antes de encolar

. /etc/profile                         # ANTES de set -u: /etc/profile usa variables sin definir
set -euo pipefail

# ---- Configuración del proyecto (se puede sobrescribir con --export=ALL,VAR=valor) -----------------
export PROY=${PROY:-$SLURM_SUBMIT_DIR}
export CMD_TILE=${CMD_TILE:-python3 -u $PROY/procesar_tile.py}   # se llama: CMD_TILE entrada dir_salida
P=${P:-$SLURM_CPUS_PER_TASK}           # tiles simultáneos; bajarlo si la RAM no alcanza (ver references/cpu-tiles.md)
export SEG_TILE=${SEG_TILE:-600}       # tiempo máximo esperado de un tile (medir con medir_tile.sbatch)
MARGEN_SEG=${MARGEN_SEG:-300}          # 5 min en short; 15 min (900) en multi
COPIAR_ENTRADA=${COPIAR_ENTRADA:-1}    # 1: copiar los tiles del lote al /scratch; 0: leerlos del /home
# ------------------------------------------------------------------------------------------------------

# Un hilo por proceso: el paralelismo lo da xargs. Sin esto, GDAL/NumPy lanzan hilos de más y se pisan.
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 GDAL_NUM_THREADS=1

LOTE=$(printf '%s/lotes/lote_%04d.txt' "$PROY" "${SLURM_ARRAY_TASK_ID:?usar sbatch --array}")
[ -f "$LOTE" ] || { echo "no existe $LOTE (correr armar_lotes.sh)" >&2; exit 1; }
export SCRATCH_DIR=/scratch/$USER/$SLURM_JOB_ID
mkdir -p "$SCRATCH_DIR" "$PROY"/estado/ok "$PROY"/estado/fallo "$PROY"/logs/tiles "$PROY"/salida

FIN=$(squeue -h -j "$SLURM_JOB_ID" -o %e)
export HASTA_EPOCH=$(( $(date -d "$FIN" +%s) - MARGEN_SEG ))
echo "$(date '+%F %T') lote $SLURM_ARRAY_TASK_ID en $(hostname): $P procesos, para a las $(date -d @"$HASTA_EPOCH" '+%T')"

# Tiles pendientes del lote (los que no tienen estado/ok/).
PEND="$SCRATCH_DIR/pendientes.txt"
: > "$PEND"
while IFS= read -r rel; do
    n=$(basename "$rel"); n=${n%.*}
    [ -e "$PROY/estado/ok/$n" ] || printf '%s\n' "$rel" >> "$PEND"
done < "$LOTE"
NPEND=$(wc -l < "$PEND")
echo "$NPEND de $(wc -l < "$LOTE") tiles pendientes"
[ "$NPEND" -gt 0 ] || exit 0

source "$PROY/scripts/entorno_scratch.sh"

if [ "$COPIAR_ENTRADA" = 1 ]; then
    NECESITA=$(cd "$PROY/entrada" && tr '\n' '\0' < "$PEND" | du -cb --files0-from=- | tail -1 | cut -f1)
    LIBRE=$(df -B1 --output=avail "$SCRATCH_DIR" | tail -1)
    if (( NECESITA * 2 > LIBRE )); then
        echo "el lote ocupa $((NECESITA>>30)) GB y hay $((LIBRE>>30)) GB libres en /scratch: leo del /home" >&2
    else
        _t0=$(date +%s)
        mkdir -p "$SCRATCH_DIR/in"
        if command -v rsync >/dev/null; then
            rsync -a --files-from="$PEND" "$PROY/entrada/" "$SCRATCH_DIR/in/"
        else
            (cd "$PROY/entrada" && tr '\n' '\0' < "$PEND" | xargs -0 cp --parents -t "$SCRATCH_DIR/in/")
        fi
        echo "entrada copiada al /scratch: $((NECESITA>>20)) MB en $(( $(date +%s) - _t0 )) s"
    fi
fi

tr '\n' '\0' < "$PEND" | xargs -0 -P "$P" -n 1 bash "$PROY/scripts/procesar_tile.sh"

OKS=0; FALLOS=0
while IFS= read -r rel; do
    n=$(basename "$rel"); n=${n%.*}
    if [ -e "$PROY/estado/ok/$n" ]; then OKS=$((OKS+1)); elif [ -e "$PROY/estado/fallo/$n" ]; then FALLOS=$((FALLOS+1)); fi
done < "$LOTE"
echo "$(date '+%F %T') fin del lote $SLURM_ARRAY_TASK_ID: $OKS ok, $FALLOS fallidos, $(( $(wc -l < "$LOTE") - OKS - FALLOS )) pendientes"
