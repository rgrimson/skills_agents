#!/bin/bash
# Plantilla mínima de un job de GPU en Mendieta (adaptada de tuneo_mendieta.sbatch del repo land2vec).
# Copiar, cambiar nombre, partición, tiempo y el comando final. Encolar desde ~/proyecto con: sbatch plantilla.sh
# Ver references/gpu-mendieta.md y references/lecciones-mendieta.md (§1 entorno en /scratch, §3 orden de /etc/profile, §4 nombres, §9 y §12 parada).
#SBATCH --job-name=mi_job               # distinto de otros jobs pendientes si se usa singleton (lecciones §4)
#SBATCH --partition=short               # short: hasta 1 h, arranca rápido; multi: hasta 2 días, puede esperar un día
#SBATCH --time=0-01:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=10              # mínimo medio nodo: 10 cores + 1 GPU
#SBATCH --gres=gpu:1
#SBATCH --output=logs/%x-%j.out         # la carpeta logs/ tiene que existir antes de encolar
#SBATCH --mail-user=USUARIO@dominio
#SBATCH --mail-type=FAIL,TIME_LIMIT     # agregar BEGIN,END si se quiere aviso de inicio y fin

. /etc/profile                          # ANTES de set -u (lecciones §3)
set -euo pipefail

# Entorno: .tar empaquetado en la cabecera, descomprimido en el /scratch local (lecciones §1).
# ENTORNO_TAR apunta al .tar que arma scripts/empaquetar_entorno.sh.
export ENTORNO_TAR=${ENTORNO_TAR:-$PWD/entorno/py313.tar}
source scripts/entorno_scratch.sh

# Parar solo antes del límite (lecciones §9 y §12): tiempo restante del job menos un margen.
MARGEN_SEG=${MARGEN_SEG:-300}           # 5 min en jobs de 1 h; 15 min en jobs de 2 días
FIN=$(squeue -h -j "$SLURM_JOB_ID" -o %e)
SEG_RESTANTES=$(python3 -c "import datetime as d; print(int((d.datetime.fromisoformat('$FIN') - d.datetime.now()).total_seconds()) - $MARGEN_SEG)")
HASTA_EPOCH=$(( $(date +%s) + SEG_RESTANTES ))   # plazo absoluto que el programa debe respetar por sí mismo

echo "$(date '+%F %T') job $SLURM_JOB_ID en $(hostname), GPU $CUDA_VISIBLE_DEVICES, para a las $(date -d @$HASTA_EPOCH '+%T')"

# python -u: sin buffer, para no perder el log si el job muere (lecciones §2).
# El programa debe: guardar checkpoints atómicos, retomar con el mismo comando y salir solo al llegar a HASTA_EPOCH.
python3 -u mi_script.py --hasta-epoch "$HASTA_EPOCH"
