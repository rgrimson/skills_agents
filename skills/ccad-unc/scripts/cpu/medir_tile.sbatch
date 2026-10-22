#!/bin/bash
# Mide tiempo y memoria por tile, procesando unos pocos tiles reales con el mismo envoltorio que la corrida
# grande. Pensado para Mulatona (acepta jobs de 1 core), pero también corre en Serafín (nodo completo).
# Encolar desde la carpeta del proyecto, después de crear_entorno.sh y armar_lotes.sh:
#
#   sbatch scripts/medir_tile.sbatch                                  # 3 tiles, uno por vez
#   sbatch --export=ALL,N=6,P=3 -c 3 scripts/medir_tile.sbatch        # 6 tiles, 3 a la vez (ver si se frenan)
#
# La salida va a prueba/ (no toca estado/ ni salida/ de la corrida real) y se borra en cada medición.
# El resumen queda al final del log: segundos y RAM máxima por tile, y segundos por GB de entrada.
#
#SBATCH --job-name=medir_tile
#SBATCH --partition=short
#SBATCH --time=0-00:50
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --output=logs/%x-%j.out

. /etc/profile
set -euo pipefail

export PROY=${PROY:-$SLURM_SUBMIT_DIR}
export CMD_TILE=${CMD_TILE:-python3 -u $PROY/procesar_tile.py}
N=${N:-3}
P=${P:-1}
LISTA=${LISTA:-$PROY/lotes/todos.txt}       # o un archivo propio con tiles representativos
export SEG_TILE=0                           # medir siempre, aunque el tile tarde mucho
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 GDAL_NUM_THREADS=1

export SCRATCH_DIR=/scratch/$USER/$SLURM_JOB_ID
export ESTADO_DIR=$PROY/prueba/estado SALIDA_DIR=$PROY/prueba/salida LOGS_TILES=$PROY/prueba/logs
rm -rf "$PROY/prueba"
mkdir -p "$SCRATCH_DIR" "$ESTADO_DIR"/ok "$ESTADO_DIR"/fallo "$SALIDA_DIR" "$LOGS_TILES"

FIN=$(squeue -h -j "$SLURM_JOB_ID" -o %e)
export HASTA_EPOCH=$(( $(date -d "$FIN" +%s) - 120 ))

source "$PROY/scripts/entorno_scratch.sh"
echo "nodo $(hostname), $(nproc) cores visibles, $P a la vez"

# Tiles repartidos a lo largo de la lista (no sólo los primeros), para que la muestra sea más variada.
TOT=$(wc -l < "$LISTA")
PASO=$(( TOT / N > 0 ? TOT / N : 1 ))
awk -v p="$PASO" -v n="$N" 'NR % p == 1 || p == 1 { print; if (++k == n) exit }' "$LISTA" > "$SCRATCH_DIR/muestra.txt"

T0=$(date +%s)
tr '\n' '\0' < "$SCRATCH_DIR/muestra.txt" | xargs -0 -P "$P" -n 1 bash "$PROY/scripts/procesar_tile.sh"
TOTAL=$(( $(date +%s) - T0 ))

echo
echo "== Resumen (P=$P, nodo $(hostname))"
printf '%-40s %8s %10s %10s %8s\n' tile MB_entrada segundos RAM_MB s_por_GB
while IFS= read -r rel; do
    n=$(basename "$rel"); n=${n%.*}
    mb=$(( $(stat -c %s "$PROY/entrada/$rel") >> 20 ))
    if [ -e "$ESTADO_DIR/ok/$n" ]; then
        s=$(cat "$ESTADO_DIR/ok/$n")
        kb=$(awk -F': ' '/Maximum resident set size/ {print $2}' "$LOGS_TILES/$n.log")
        ram=$(( ${kb:-0} / 1024 ))
        sgb=$(( mb > 0 ? s * 1024 / mb : 0 ))
        printf '%-40s %8s %10s %10s %8s\n' "$n" "$mb" "$s" "$ram" "$sgb"
    else
        printf '%-40s %8s %10s\n' "$n" "$mb" "FALLÓ: $(cat "$ESTADO_DIR/fallo/$n" 2>/dev/null)"
    fi
done < "$SCRATCH_DIR/muestra.txt"
echo "tiempo total: $TOTAL s"
