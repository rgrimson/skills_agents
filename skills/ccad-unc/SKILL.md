---
name: ccad-unc
description: Usar los clusters de UNC Supercómputo / CCAD (Universidad Nacional de Córdoba) - Mendieta (GPU A30), Serafín, Mulatona, Eulogia - por SSH y Slurm, tanto para entrenar modelos con GPU como para procesar muchos archivos en CPU (tiles LiDAR LAS/LAZ, rásters, imágenes). Usar siempre que haya que conectarse a *.ccad.unc.edu.ar, elegir cluster o partición, subir datos con rsync, preparar un entorno de Python (PyTorch, PDAL, GDAL), medir cuánto tarda un trabajo, escribir o encolar scripts sbatch o job arrays, seguir jobs (squeue, sacct, seff, jobmetrics), reintentar lo que falló o traer resultados. También ante dudas de normas de uso del CCAD, colas, límites de tiempo, /scratch o errores de jobs (TIMEOUT, OUT_OF_MEMORY, DependencyNeverSatisfied, imports lentos, nodos subutilizados), aunque no se nombre el cluster.
---

# UNC Supercómputo (CCAD-UNC)

Fuente: la wiki oficial, https://wiki.ccad.unc.edu.ar/ (fuente en https://gitlab.com/ccad/wiki-rtd).
Este archivo tiene lo común. El flujo completo depende del tipo de trabajo:

| Tipo de trabajo | Cluster | Leer | Scripts |
|---|---|---|---|
| **Usa GPU** (entrenar o correr redes con PyTorch, etc.) | Mendieta | [references/gpu-mendieta.md](references/gpu-mendieta.md) y [references/lecciones-mendieta.md](references/lecciones-mendieta.md) | `scripts/gpu/` |
| **CPU, muchos archivos independientes** (tiles LiDAR, rásters, imágenes) | Serafín (producción), Mulatona (pruebas) | [references/cpu-tiles.md](references/cpu-tiles.md) | `scripts/cpu/` |

Resumen de la wiki página por página, con URLs: [references/wiki.md](references/wiki.md).
Los scripts de `scripts/gpu/` o `scripts/cpu/` se copian a `PROYECTO/scripts/` en el cluster y se corren desde la carpeta del proyecto.
Para otros trabajos de CPU (un programa MPI, un solo proceso largo), seguir las reglas de este archivo y las páginas de la wiki sobre Slurm, Spack y paralelizar dentro de un job.

## Elegir cluster

| | Mendieta | Mulatona | Eulogia | Serafín | Boogie |
|---|---|---|---|---|---|
| Uso | Cómputo con GPU | Trabajos pequeños | Sólo software preinstalado | Propósito general | JupyterHub |
| Nodos | 19 | 7 | 32 | 64 | 8 |
| Cores/nodo | 20 (Xeon E5-2680 v2, **sin AVX2**) | 32 (Xeon E5-2683 v4) | 64C/256T (Xeon Phi 7210) | 64 (EPYC 7532) | 128 (EPYC 7B12) |
| GPU/nodo | **2 × NVIDIA A30 (24 GB)** | - | - | - | - |
| RAM/nodo | 64 GB | 128 GB | 96 GB | 256 GB | 512 GB |
| /scratch | 400 GB SSD | 95 GB SSD | 200 GB SSD | 1 TB NVMe | - |
| Job mínimo | ½ nodo (10 cores, 1 GPU) | 1 core | 1 nodo | 1 nodo | 1 core |
| Host | mendieta.ccad.unc.edu.ar | mulatona… | eulogia… | serafin… | jupyterhub.ccad.unc.edu.ar |

- **Mendieta sólo para programas que usan GPU.** Trabajo de CPU ahí ocupa GPUs que otros necesitan, y sus CPUs son los más viejos.
- **Serafín para CPU en serio**, llenando nodos enteros. **Mulatona para medir y probar** con pocos cores.
- **Eulogia** (Xeon Phi) sólo con software preinstalado (`module av`); Python con bibliotecas propias anda mal.

### Particiones

| | Mendieta | Mulatona | Eulogia | Serafín |
|---|---|---|---|---|
| `short` | hasta 1 h (default) | hasta 1 h, 1 nodo (default) | hasta 1 h | hasta 1 h (default) |
| `multi` | hasta 2 días | - | hasta 4 días (default) | hasta 2 días |
| `mono` | - | hasta 2 días, 1 nodo | - | - |

`short` suele arrancar mucho antes que `multi`: conviene partir el trabajo en jobs de menos de una hora. Ver la cola real con `sinfo` y `squeue -p multi`.

## Reglas (de la wiki y del CCAD)

1. **Todo cálculo va por Slurm.** En la cabecera (nodo de login) sólo se edita, instala, empaqueta, compila y encola. Scripts livianos (leer un CSV, contar archivos) están bien; procesar, no.
2. **Mendieta: 10 cores por cada GPU** (aviso al iniciar sesión).
3. **Respetar los límites de la partición.** Partir un trabajo largo en jobs más cortos que guardan y se retoman es práctica de la propia wiki.
4. **Slurm cobra lo reservado, no lo usado.** Llenar lo que se pide y revisar la eficiencia con `seff`. El CCAD tiene tarifario por hora-core (RR-469-2021).
5. **Probar chico antes de lanzar grande:** un job corto en `short` que haga lo mismo que el real.
6. **Las claves SSH son personales** y la cuenta no se comparte. Ver "Seguridad para agentes".
7. **Uso gratuito sólo para proyectos de índole pública.** Si en algún momento hay fin comercial, avisar a director@ccad.unc.edu.ar.
8. **Citar el uso de recursos** en publicaciones: https://supercomputo.unc.edu.ar/equipamiento/citar-recursos/

## Almacenamiento

- **`/home`**: remoto (NFS), permanente y compartido por la cabecera y los nodos del cluster. **Lento para mucha E/S**, incluido cargar bibliotecas grandes: por eso los entornos se empaquetan en un `.tar` y se descomprimen en el `/scratch` al empezar cada job.
- **`/scratch`**: disco local de cada nodo, rápido. **Se borra al terminar el job.** Para conservar algo: copiarlo al /home antes de terminar o usar `sgather`.
- **`/tmp`**: vive en la RAM del nodo (hasta 50 %). Sólo archivos chicos.
- Antes de subir muchos datos, ver espacio y cuota (`df -h ~`, `quota -s`) y, si no está claro el límite, preguntar a soporte.

## Conexión

```bash
ssh -o BatchMode=yes USUARIO@serafin.ccad.unc.edu.ar 'comando'
```

- Sólo claves SSH. Con `BatchMode`, si la clave no está disponible falla en vez de pedir contraseña. La primera conexión puede necesitar `-o StrictHostKeyChecking=accept-new`.
- **Si el usuario tiene alias** en `~/.ssh/config` (verlo con `grep -B1 -A3 ccad ~/.ssh/config`), usarlos: `ssh serafin 'comando'`.
- **No asumir que el /home es el mismo en todos los clusters:** en 2026-10, Serafín y Mulatona tenían /home independientes. Comprobarlo: `ssh serafin 'touch ~/.prueba_home' && ssh mulatona 'ls ~/.prueba_home'`. Si no es compartido, hay que subir el proyecto y armar el entorno en cada cluster que se use.
- Estado de los clusters: https://stats.uptimerobot.com/eLhTV5CMni
- El cluster no tiene git-lfs: copiar el árbol de trabajo con rsync en lugar de clonar un repo con archivos LFS.

## Encolar y seguir

```bash
sbatch job.sh                                    # devuelve el JOBID (--parsable: sólo el número)
sbatch --test-only job.sh                        # estima el arranque sin encolar
sbatch --array=1-20%4 job.sh                     # job array, como máximo 4 tareas a la vez
squeue --me --start                              # cola y arranque estimado
sbatch --dependency=afterok:JOBID job2.sh        # encadenar (afterany: arranca aunque el otro falle)
scontrol update JobId=N MailType=END,FAIL MailUser=x@y   # cambiar un job pendiente
scontrol show job N; scancel N
sacct -X -j N -o JobID%20,State,Start,Elapsed,ExitCode
seff N; jobmetrics N                             # eficiencia; Grafana (stats.ccad.unc.edu.ar)
```

- Motivos de espera comunes: `Priority`, `Resources`, `Dependency`, `DependencyNeverSatisfied` (la dependencia falló: cancelar y reencolar) y `AssocMaxJobsLimit` (tope de jobs simultáneos).
- `seff` y "Job Metrics" se agregan solos al final del log del job.
- Los mails de Slurm (`--mail-type=FAIL,END --mail-user=…`) funcionan y se pueden agregar a un job pendiente.

## Errores típicos (todos los clusters)

- **El job falla en 1 s con `HISTCONTROL: unbound variable`:** `set -u` antes de `. /etc/profile`. Cargar primero `. /etc/profile` y después `set -euo pipefail` (lecciones §3).
- **No aparece el log:** falta la carpeta de `--output`; Slurm no la crea. `mkdir -p logs` antes de encolar.
- **Corregí el sbatch y no cambió nada:** Slurm guarda una copia al encolar. Cancelar y reencolar (los `.py` y los `source` sí se leen del disco al correr).
- **El log queda vacío cuando el job muere:** Python guarda la salida en un buffer. Usar `python -u` o `flush=True` (lecciones §2).
- **Un job tarda muchísimo en arrancar el programa:** bibliotecas cargadas desde el /home. Empaquetar el entorno y descomprimirlo en el /scratch.
- **`TIMEOUT`:** el programa tiene que parar solo antes del límite y poder retomar; ver el flujo de cada tipo de trabajo.
- **Las líneas `#SBATCH` se ignoran:** sólo se leen hasta el primer comando del script.

## Seguridad para agentes

- **Autenticación:** usar sólo el agente SSH del usuario (`SSH_AUTH_SOCK`, que VS Code reenvía a los devcontainers). **Nunca** pedir, leer, copiar ni pegar la clave privada. Si el usuario ofrece pasarla, rechazarlo y proponer el agente o una clave nueva cuya pública agregue él (procedimiento "Desde otra computadora" de la wiki).
- **Conexiones:** cada `ssh` ejecuta un comando y se cierra; no dejar sesiones ni ControlMaster abiertos.
- **Confirmar con el usuario antes de:**
  - encolar jobs (salvo `--test-only`) o cambiarlos con `scontrol update`, porque consumen horas de su cuenta;
  - cancelar jobs;
  - borrar o sobrescribir archivos en el cluster;
  - subir datos grandes o instalar cosas fuera del proyecto.
  Consultar el estado, leer logs y resúmenes no necesita confirmación.
- **Banner:** las conexiones muestran un recuadro de bienvenida. Se puede filtrar del output, pero **leerlo primero**: ahí aparecen avisos de normas (por ejemplo, "10 cores por GPU") y mantenimientos. El aviso de *Novedades* sólo sale en sesiones interactivas.
- **Aviso "post-quantum" de OpenSSH ≥ 10:** el servidor usa OpenSSH 8.0. No impide trabajar.
- **Antes de commitear o subir cualquier cosa,** buscar claves o tokens en lo que se va a publicar.

## Ayuda

- Wiki con buscador: https://wiki.ccad.unc.edu.ar/
- Zulip de usuarios (anuncios de incidentes y mantenimientos): https://ccadunc.zulipchat.com/
- Soporte: `soporte@ccad.unc.edu.ar`, indicando usuario, cluster, directorio, script sbatch y archivo con el error.
- Reunión virtual: https://calendly.com/ccad-soporte-ale/consulta
- Pedido de cuenta: https://forms.gle/xu4owamaRKqpxWoy7 (hay que repetirlo en cada reempadronamiento).
- Cómputo intensivo con exclusividad: "Ventanilla permanente de uso intensivo" en supercomputo.unc.edu.ar/servicios.
