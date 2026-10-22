# Flujo de trabajo con GPU en Mendieta

Leer junto con [lecciones-mendieta.md](lecciones-mendieta.md) antes del primer job: cada punto costó al menos un job fallido.
Scripts en `scripts/gpu/`; se copian a `PROYECTO/scripts/` en el cluster.

**Si estás en el repo land2vec:** `scripts/cluster/` de ese repo ya tiene una implementación completa que funcionó (tuneo de un autoencoder en Mendieta, con empaquetado del entorno, cadenas de jobs y reanudación). Ahí usar esos scripts y sus rutas (`scripts/cluster/...`, entorno en `entorno/py313_tuneo.tar`), no los de esta skill.

## Reglas propias de Mendieta

- **Sólo para programas que usan GPU.** Al iniciar sesión aparece el aviso: pedir **10 cores por cada GPU**.
- El job mínimo es medio nodo: `--cpus-per-task=10 --gres=gpu:1`. Nodo completo: 20 cores y `--gres=gpu:2`.
- Los Xeon E5-2680 v2 (Ivy Bridge) **no tienen AVX2**: Python y bibliotecas para x86-64 base, no v3.
- 64 GB de RAM por nodo (unos 30 GB en medio nodo) y 400 GB de /scratch SSD.

## 1. Llevar el código

```bash
rsync -avz --exclude __pycache__ --exclude .venv src scripts setup.py USUARIO@mendieta.ccad.unc.edu.ar:PROYECTO/
rsync -av scripts/gpu/ USUARIO@mendieta.ccad.unc.edu.ar:PROYECTO/scripts/     # los de esta skill
```

Copiar el árbol de trabajo, no un `git clone`, si hay cambios sin commitear o archivos LFS (el cluster no tiene git-lfs). **Crear `logs/` antes de encolar.**

## 2. Entorno de Python (en la cabecera)

Los nodos no tienen internet: todo se instala en la cabecera. Funciona `uv` (un solo binario en `~/.local/bin`):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh                       # una vez
cd PROYECTO
uv venv --python 3.13 --python-preference only-managed                 # Python de uv, relocalizable
uv pip install torch --index-url https://download.pytorch.org/whl/cu126   # A30 = sm_80; cu126 o cu128 (driver 580 visto en 2026-10)
uv pip install -e .                                                    # o lo que use el proyecto
bash scripts/empaquetar_entorno.sh                                     # → entorno/py313.tar
```

- `--python-preference only-managed` evita que `uv` tome el Python de Miniconda, que no es relocalizable (lecciones §1).
- **No correr el entorno desde el /home:** `import torch` tardó 710 s en un nodo. El sbatch descomprime el `.tar` en el /scratch con `scripts/entorno_scratch.sh` (6,6 GB en 36 s).
- **Rehacer el `.tar` cada vez que cambie el `.venv`.** `uv cache clean` libera `~/.cache/uv`.
- La wiki recomienda Miniconda; también sirve, empaquetando con conda-pack como en `scripts/cpu/crear_entorno.sh` (con torch para CUDA en lugar de los paquetes geoespaciales).

## 3. Probar antes de lanzar lo largo

`sbatch scripts/prueba_mendieta.sbatch` corre unos minutos en `short` con el mismo entorno y la misma forma de lanzar Python que el job real, y muestra la hora de cada etapa (import, CUDA, matmul). Mejor aún, **una hora del trabajo real en `short`**: así aparecieron dos errores que la prueba sintética no mostró (lecciones §3 y §5).

## 4. Script sbatch

Partir de `scripts/plantilla-sbatch.sh`. Lo esencial:

```bash
#SBATCH --partition=multi            # short: hasta 1 h
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=10           # 10 por GPU
#SBATCH --gres=gpu:1                 # GPUs por nodo; 2 = nodo completo con 20 cores
#SBATCH --time=2-00:00
#SBATCH --output=logs/%x-%j.out

. /etc/profile                       # ANTES de `set -u` (lecciones §3)
set -euo pipefail
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
source scripts/entorno_scratch.sh
python3 -u programa.py
```

- Con `--gres`, `CUDA_VISIBLE_DEVICES` numera desde 0 las GPUs asignadas.
- Una sola corrida chica no llena una A30: conviene correr varias en paralelo (lecciones §10).
- Sesión interactiva con GPU: `srun --gres=gpu:1 --pty bash`.

## 5. Trabajos que superan el límite de tiempo

- El programa tiene que **guardar checkpoints atómicos y poder retomar con el mismo comando**.
- Hacerlo **parar solo antes del límite**: la plantilla calcula `HASTA_EPOCH` con `squeue -h -j $SLURM_JOB_ID -o %e` menos un margen (5 min en `short`, 15 en `multi`) y se lo pasa al programa.
- Como refuerzo, `#SBATCH --signal=B:TERM@300`, pero sin depender sólo de SIGTERM (lecciones §12).
- Volver a encolar el mismo script cuantas veces haga falta. Para que dos jobs no pisen el mismo trabajo: `--dependency=singleton` con nombres distintos para las pruebas (lecciones §4) o `afterany`.
- Probar la **retoma** en GPU, no sólo el arranque (lecciones §5).

## 6. Traer resultados

```bash
rsync -avz --exclude ckpt.pt USUARIO@mendieta.ccad.unc.edu.ar:PROYECTO/resultados/ resultados/
```
