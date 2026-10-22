# Lecciones de la práctica en Mendieta (no están en la wiki)

Salen de correr el tuneo de un autoencoder en PyTorch en Mendieta, del 2026-10-09 al 2026-10-10: 24 configuraciones, 1 A30, más de 7 h. Cada punto costó al menos un job fallido. La implementación original está en `scripts/cluster/` del repo land2vec; la versión general, en `scripts/gpu/` de esta skill.

## 1. El /home es lento para cargar bibliotecas: correr el entorno desde el /scratch
- **Síntoma:** un job de prueba moría por `TIMEOUT` sin imprimir nada, con el 0,2 % de CPU usada. Con `faulthandler` apareció la causa: estaba trabado en `import torch` (`torch/__init__.py`, `_load_global_deps`, `ctypes.CDLL`). **En el nodo, `import torch` tardó 710 s; en la cabecera, con los archivos en caché, 4 s.**
- **Causa:** al cargar unos 3 GB de `.so` (CUDA, cuBLAS, cuDNN) desde el NFS, el sistema hace miles de lecturas chicas, y cada una tiene la latencia de la red.
- **Solución:**
  1. En la cabecera, empaquetar en un solo `.tar` el Python independiente de `uv` (`~/.local/share/uv/python/cpython-3.13.*`) con el `site-packages` del venv metido adentro. Así los `.pth` se procesan solos. Ver `scripts/gpu/empaquetar_entorno.sh`.
  2. Al empezar el job: `tar -xf entorno.tar -C /scratch/$USER/$SLURM_JOB_ID/py` y poner `/scratch/$USER/$SLURM_JOB_ID/py/bin` primero en el `PATH`, más `PYTHONNOUSERSITE=1`. Ver `scripts/gpu/entorno_scratch.sh`.
  3. Resultado: 6,6 GB copiados en 36 s, `import torch` en 4 s.
- **Rehacer el `.tar` cada vez que cambie el venv.**
- `uv venv` toma el primer Python 3.13 del `PATH`, que puede ser el de Miniconda y no es relocalizable. Usar `uv venv --python-preference only-managed`.
- Python x86-64 **base**: los Xeon Ivy Bridge de Mendieta no tienen AVX2.

## 2. La salida de Python se pierde si el job muere
Si stdout va a un archivo, Python lo guarda en un buffer, y si Slurm mata el proceso, el log queda vacío. Usar `python -u` o `print(..., flush=True)`. Para diagnosticar cuelgues: `python -X faulthandler` más `faulthandler.dump_traceback_later(60, repeat=True)`, que vuelca la pila cada 60 s.

Evitar `srun python - <<EOF` (el código por la entrada estándar a través de srun). Lanzar la prueba **igual** que el job real: si el real corre `python3 script.py`, la prueba también.

## 3. `set -u` antes de `/etc/profile` mata el job
El `/etc/profile` de los nodos usa `HISTCONTROL` sin definirla. Con `set -euo pipefail` antes de `. /etc/profile`, el job termina en 1 s con `FAILED` y `HISTCONTROL: unbound variable`. Hay que cargar `. /etc/profile` primero y después `set -euo pipefail`.

## 4. `--dependency=singleton` también espera a los jobs *pendientes* con el mismo nombre
`singleton` deja que un job arranque sólo cuando no queda otro del mismo usuario y nombre encolado antes, **incluidos los pendientes**. Un job corto de prueba con el mismo nombre que uno largo pendiente queda bloqueado hasta que el largo termine.
- Darles nombres distintos, por ejemplo `--job-name=x_corto`.
- Encadenar con `afterany:JOBID`. Se puede cambiar un job pendiente con `scontrol update JobId=N Dependency=afterany:M`, sin perder su lugar en la cola.

## 5. Probar la *retoma* en GPU, no sólo el arranque
Un programa con checkpoints se había probado parando y retomando en CPU, pero en GPU falló al retomar: `torch.load(ckpt, map_location="cuda")` también manda a la GPU los estados del generador aleatorio guardados, y `torch.set_rng_state` / `torch.cuda.set_rng_state` exigen un `ByteTensor` **en la CPU** (`TypeError: RNG state must be a torch.ByteTensor`). Solución: `.cpu()` sobre `st["rng_cpu"]` y `st["rng_cuda"]`.

Lección general: la prueba más útil fue **una hora del trabajo real en `short`**, retomando checkpoints existentes. Encontró dos errores que la prueba sintética no mostró.

## 6. Slurm guarda una copia del script
Lo que se ejecuta es el `.sbatch` tal como estaba **al encolar**. Si se corrige después, hay que hacer `scancel` y volver a encolar. Los archivos que el script llama, como `.py` o un `source`, sí se leen del disco cuando corren.

## 7. Dependencias que fallan
- `--dependency=afterok:N`: si N falla o vence por tiempo, el dependiente queda en `DependencyNeverSatisfied` para siempre y hay que cancelarlo y reencolarlo.
- `afterany:N`: arranca igual, sin importar cómo terminó N.

## 8. Estimar el arranque antes de decidir
- `sbatch --test-only -p multi -N1 -n1 -c 10 --gres=gpu:1 -t 2-00:00 --wrap=true` estima el arranque sin encolar.
- `squeue --me --start` hace lo mismo para lo ya encolado.
- En 2026-10, un viernes con 60 o más jobs pendientes, `multi` estimaba de 1 a 4 días y `short`, minutos u horas. Las estimaciones son pesimistas y en la práctica arrancó antes.
- Pedir menos tiempo en `multi` no adelantó la estimación.

## 9. Parar solo antes del límite
Calcular el tiempo restante dentro del job y pasárselo al programa:
```bash
FIN=$(squeue -h -j "$SLURM_JOB_ID" -o %e)
MAX_HORAS=$(python3 -c "import datetime as d; print(((d.datetime.fromisoformat('$FIN') - d.datetime.now()).total_seconds() - $MARGEN_SEG) / 3600)")
```
- Margen: 5 min en jobs de 1 h, 15 min en jobs de 2 días.
- El programa deja de lanzar trabajo nuevo, guarda y sale con código 0. El job termina `COMPLETED` y no `TIMEOUT`.
- Volver a encolar el mismo comando para seguir.

## 10. Rendimiento visto (A30, nodo ivb)
- Autoencoder transformer chico (n_embd 128, 2 capas, lote 128), una corrida sola: 79 pasos/s; en una GTX 1060, 41,5.
- Con 3 corridas a la vez en una A30: de 74 pasos/s en las chicas a 4 en las de n_embd 256 con 4 capas y lote 512. Una sola corrida chica no llena la A30, así que conviene tener varias en paralelo.
- k-medias de sklearn (22.000 × 8, 7 valores de k × 10 arranques): 6,6 s en el Xeon E5-2680 v2.
- Matmul fp32 4096²: 6,3 TFLOP/s sin TF32.
- El job registra como memoria usada el caché de archivos del `.tar` descomprimido (14-16 GB de los 30 GB de medio nodo). Se libera si hace falta.

## 11. Varios
- **Mails de Slurm** (`--mail-type=BEGIN,END,FAIL --mail-user=…`): funcionan. El asunto trae el estado y el código de salida. Se pueden agregar a un job pendiente con `scontrol update`.
- **`seff` y "Job Metrics"** se agregan solos al final del log.
- **Banner:** las conexiones con `ssh host 'comando'` sólo muestran el recuadro "Si tiene problemas para ingresar…". El aviso de *Novedades* ("10 cores por GPU") sale en sesiones interactivas.
- **El /home es el mismo en la cabecera y en los nodos,** así que `touch archivo_STOP` desde la cabecera sirve para parar un programa que lo vigile.
- **Python en la cabecera:** correr scripts livianos, como leer CSV o mostrar el estado, está bien; entrenar o calcular, no.
- **`uv` deja caché en `~/.cache/uv`;** se libera con `uv cache clean`.
- **git-lfs no está en el cluster:** copiar el árbol de trabajo con rsync y no clonar el repo si tiene archivos LFS.

## 12. No confiar sólo en SIGTERM para parar a tiempo
- **Qué pasó (2026-10-14):** un job de `short` con 3 corridas en paralelo terminó en `TIMEOUT`. A la hora de parar, el lanzador mandó SIGTERM a las 3; dos guardaron y salieron, y una lo ignoró y siguió hasta que Slurm la mató. La causa quedó sin determinar y no se reprodujo en CPU.
- **Qué lo arregló (probado en GPU: 5 jobs de 1 h seguidos, todos `COMPLETED`, ninguna corrida muerta a la fuerza):**
  1. Cada proceso recibe su propio plazo absoluto (`--hasta-epoch`, hora Unix) y para solo al llegar, sin depender de ninguna señal.
  2. El lanzador reenvía SIGTERM cada 30 s después de la hora de corte, y si pasados 120 s una corrida sigue viva la mata con SIGKILL (el último checkpoint ya está guardado).
  3. No se lanza una corrida nueva si quedan menos de 180 s de plazo (el arranque del proceso solo ya consume ese margen).
  4. Un proceso lanzado con el plazo vencido sale enseguida, antes de importar `torch`.
- **Para probar el mecanismo sin gastar GPU:** simular señales perdidas anulando `send_signal`, y un proceso hijo que ignore SIGTERM; verificar que cada caso termina en el tiempo previsto. Ver `plantilla-sbatch.sh` para pasar el plazo al programa.
