#!/bin/bash
# Prueba del entorno en un nodo de cómputo de Mendieta (partición short, unos minutos).
#   sbatch scripts/prueba_mendieta.sbatch && tail -f logs/prueba-*.out
# Lanza Python igual que plantilla-sbatch.sh (directo, sin srun). Salida sin buffer y con la hora de cada etapa;
# si algo se cuelga, faulthandler vuelca cada 60 s dónde está cada hilo.
#SBATCH --job-name=prueba_entorno
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=10
#SBATCH --gres=gpu:1
#SBATCH --time=0-0:15
#SBATCH --output=logs/prueba-%j.out

. /etc/profile
source scripts/entorno_scratch.sh
echo "nodo $(hostname), CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
nvidia-smi --query-gpu=name,driver_version,memory.total,compute_mode,persistence_mode --format=csv
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
python3 -u -X faulthandler scripts/prueba_entorno.py
echo "código de salida: $?"
