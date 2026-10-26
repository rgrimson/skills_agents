# Flujo de trabajo por tiles en CPU (Helvetios y Serafín)

Para muchos archivos independientes que se procesan igual: nubes LiDAR (LAS/LAZ), rásters, imágenes.
**Helvetios** sirve para todo: mediciones con pocos cores y producción en nodos de 36 cores. **Serafín** es la alternativa, con nodos de 64 cores pero job mínimo de un nodo entero. (Mulatona, donde se medía antes, se retira el 28/10/2026.)
Scripts en `scripts/cpu/`; se copian a `PROYECTO/scripts/` en el cluster.
En los ejemplos, `helvetios` y `serafin` son alias de `~/.ssh/config` (ver SKILL.md, "Conexión"); si no existen, usar `USUARIO@helvetios.ccad.unc.edu.ar`.

## Por qué así

- **Un job = un lote de tiles corriendo en paralelo dentro de un nodo**, con `xargs -P` y un hilo por proceso. Slurm cobra lo reservado: un tile por job desperdiciaría el nodo (en Serafín el job mínimo es un nodo entero de 64 cores).
- **Helvetios acepta jobs de pocos cores:** sirve para medir tiempo y memoria por tile sin ocupar un nodo. Pero **limita la memoria por defecto (~4,9 GB por core)**: pedir siempre `--mem`.
- El mismo `environment.yml` funciona en Serafín (Rocky 8) y Helvetios (Rocky 10), pero el entorno se arma en cada cluster, porque los /home son independientes.
- Cada tile terminado queda marcado y copiado al /home enseguida: un `TIMEOUT` no pierde lo hecho y relanzar un lote es seguro.

## Antes de empezar: ¿conviene el cluster?

Estimar primero cuánto pesa el cálculo frente a la transferencia. Referencia medida (2026-10, LiDAR del Matanza-Riachuelo, MDT de 1 m por IDW con PDAL, tiles de ~250 MB): **~35 s de un core por GB de LAS** en Mulatona; en Helvetios, 3 s por tile de mediana y 7 s como máximo (6 tiles en un job de 18 s); en Serafín, 6 tiles en un job de 21 s. Para 100 GB eso es ~1 hora-core, un par de minutos de un nodo de Serafín, mientras que subir 100 GB lleva horas.

- Si el cálculo total es de pocas horas-core, una PC con varios núcleos lo hace en menos tiempo que lo que tarda subir los datos.
- El cluster rinde cuando el procesamiento por tile es pesado (muchos filtros, morfometría, varias resoluciones, modelos), cuando se procesa muchas veces sobre datos subidos una sola vez, o cuando la memoria por tile no entra en la máquina local.
- Medir con `medir_tile.sbatch` antes de subir todo: con 3 a 6 tiles alcanza para estimar.

## Estructura del proyecto en el cluster

```
~/PROYECTO/
├── scripts/            # los de scripts/cpu/ de esta skill (copiados con rsync)
├── procesar_tile.py    # el programa del usuario (contrato abajo)
├── entrada/            # tiles subidos (.las/.laz, .tif, ...); se puede organizar en subcarpetas
├── entorno/geo.tar     # entorno empaquetado (crear_entorno.sh)
├── lotes/              # todos.txt y lote_0001.txt ... (armar_lotes.sh)
├── salida/NOMBRE/      # resultado de cada tile, aparece completo o no aparece
├── estado/ok/NOMBRE    # tile terminado (contiene los segundos que tardó)
├── estado/fallo/NOMBRE # tile fallido (contiene el motivo)
├── logs/               # logs de Slurm; logs/tiles/NOMBRE.log por tile
└── prueba/             # mediciones de medir_tile.sbatch, se pisa en cada una
```

**Contrato del programa por tile:** se llama `CMD_TILE ARCHIVO_ENTRADA DIRECTORIO_SALIDA`, escribe sólo en ese directorio (está en el /scratch), usa un hilo y sale con 0 si anduvo. `scripts/cpu/procesar_tile_ejemplo.py` es un ejemplo con PDAL (MDT de 1 m con los puntos de suelo). El nombre de cada tile (archivo sin extensión) tiene que ser único.

Si el proceso necesita tiles vecinos (por ejemplo, un buffer para evitar bordes), el programa tiene que leerlos de `$PROY/entrada/` directamente y conviene lanzar con `COPIAR_ENTRADA=0`.

## Flujo de trabajo

### 1. Subir scripts y datos (desde la máquina del usuario)

```bash
rsync -av scripts/cpu/ helvetios:PROYECTO/scripts/              # los de esta skill
rsync -av procesar_tile.py helvetios:PROYECTO/
rsync -avL --partial --info=progress2 /ruta/local/tiles/ helvetios:PROYECTO/entrada/   # -L: copia el destino de los enlaces
```

- Antes de subir mucho, ver espacio y cuota: `ssh helvetios 'df -h ~; quota -s 2>/dev/null'`. Si no está claro el límite del /home, preguntar a soporte antes de subir decenas de GB.
- Medir la velocidad primero (100 GB a 68 Mbit/s son ~3 h; a 20 Mbit/s, ~11 h): `head -c 500M /dev/zero | ssh helvetios 'cat > /dev/null'`. Una copia larga va en `tmux` o `nohup` en la máquina local. `--partial` permite retomarla.
- Verificar al final: cantidad de archivos y bytes iguales en origen y destino (`find ... | wc -l`, `du -sb`).
- El cluster no tiene git-lfs: copiar el árbol de trabajo, no clonar un repo con archivos LFS.

### 2. Entorno (en la cabecera)

```bash
ssh helvetios 'cd PROYECTO && bash scripts/crear_entorno.sh'
```

Instala Miniforge en `~/miniforge3` si falta (la wiki recomienda un entorno propio en el home), crea el entorno con mamba desde `scripts/environment.yml` (editarlo según el proyecto) y lo empaqueta con conda-pack en `entorno/geo.tar` (~1,5 GB con el `environment.yml` incluido; en el nodo se descomprime en unos segundos). Los jobs lo descomprimen en el /scratch (`entorno_scratch.sh`) porque cargar bibliotecas desde el /home (NFS) es muy lento. **Volver a correrlo cada vez que cambie `environment.yml`.** Si se usa más de un cluster, hacerlo en cada uno: los /home son independientes. En Helvetios el empaquetado tarda varios minutos (escribe 1,5 GB en BeeGFS).

### 3. Armar los lotes

```bash
ssh helvetios 'cd PROYECTO && bash scripts/armar_lotes.sh 40'
```

Lista los tiles de `entrada/`, verifica nombres únicos y escribe `lotes/todos.txt` y un archivo por lote. Para una medición alcanza con cualquier número; el definitivo sale del paso 5.

### 4. Medir

En Helvetios, con pocos cores y memoria explícita (6 tiles a la vez muestran también si se frenan entre sí):

```bash
ssh helvetios 'cd PROYECTO && mkdir -p logs && sbatch -c 6 --mem=40G --export=ALL,N=6,P=6 scripts/medir_tile.sbatch'
ssh helvetios 'cd PROYECTO && grep -A9 Resumen logs/medir_tile-JOBID.out'
```

En Serafín hay que tomar el nodo entero: `sbatch --exclusive -c 64 --export=ALL,N=12,P=12 scripts/medir_tile.sbatch`.

El final del log tiene, por tile, segundos, RAM máxima (MB) y segundos por GB de entrada. (Los nodos de Mulatona no tienen `/usr/bin/time`; la RAM la mide entonces el Python del entorno.) Después, confirmar con **un solo lote** en `short` (Helvetios: `sbatch --array=1 -c 36 --mem=0 scripts/lote_tiles.sbatch`; Serafín: `sbatch --array=1 scripts/lote_tiles.sbatch`) y mirar `seff JOBID_1`.

### 5. Dimensionar

Con `T` = segundos por tile medidos en el cluster donde se va a correr, `R` = RAM máxima por tile y `C` = cores por nodo (36 en Helvetios, 64 en Serafín):

- **Procesos por nodo** `P = min(C, RAM del nodo con margen / R)`: 180 GB en Helvetios, 230 GB en Serafín. Si `P < 64`, pasar `--export=ALL,P=...`: menos procesos que cores es mejor que quedarse sin memoria.
- **Tiles por lote** para entrar en `short` (1 h, con 5 min de margen): el nodo procesa en tandas de `P` tiles, y en 3000 s entran `floor(3000 / T)` tandas, así que `tiles por lote = P × floor(3000 / T)`. `short` arranca mucho antes que las particiones largas, así que conviene que cada lote dure ~50 min. Si un tile solo tarda más de ~40 min, usar la partición larga (`--partition=batch` en Helvetios, `multi` en Serafín; `--time=0-12:00 --export=ALL,MARGEN_SEG=900`) y recalcular con el tiempo pedido.
- **`SEG_TILE`** = el máximo medido, con un poco de margen: un tile no se empieza si no queda ese tiempo, y queda pendiente para el próximo envío.
- **El lote tiene que caber en el /scratch** (512 GB en Helvetios, 1 TB en Serafín) si se copia la entrada; el script lo verifica y, si no entra, lee del /home.
- Horas-core totales ≈ `tiles × T / 3600`; con `P` procesos por nodo de `C` cores se reservan `C / P` veces más.

Ejemplos con 394 tiles de ~250 MB:
- Medido (MDT por IDW): `T` ≈ 3 a 7 s en Helvetios → todos en **un solo lote y un solo nodo**, unos minutos. Con tiles tan rápidos, el costo fijo (descomprimir el entorno y copiar la entrada al /scratch) pesa más que el cálculo: no partir en lotes chicos.
- Pipeline pesado en Helvetios, `T` = 300 s, `R` = 3 GB → `P` = 36 y hasta 36 × 10 = 360 tiles por lote: 2 lotes, cada uno con hasta 10 tandas de 300 s (~50 min).
- `T` = 1800 s → una tanda por hora: lotes de 36 tiles, 11 lotes, y con `%4` tres rondas de una hora.

### 6. Lanzar

```bash
# Helvetios: nodo entero con toda su memoria
ssh helvetios 'cd PROYECTO && bash scripts/armar_lotes.sh N -f && mkdir -p logs && \
  sbatch --array=1-NLOTES%4 -c 36 --mem=0 --export=ALL,SEG_TILE=...,P=... scripts/lote_tiles.sbatch'
# Serafín: los valores de la plantilla ya son para su nodo de 64 cores
ssh serafin 'cd PROYECTO && bash scripts/armar_lotes.sh N -f && mkdir -p logs && \
  sbatch --array=1-NLOTES%4 --export=ALL,SEG_TILE=...,P=... scripts/lote_tiles.sbatch'
```

`lote_tiles.sbatch` hace, en cada nodo: calcula la hora de corte, saltea los tiles ya terminados, descomprime el entorno en el /scratch, copia la entrada del lote, corre `procesar_tile.sh` con `xargs -P` (un hilo por proceso: fija `OMP_NUM_THREADS=1`, `GDAL_NUM_THREADS=1`, etc.) y resume ok/fallidos/pendientes al final. Cada tile terminado se copia al /home enseguida, así que un `TIMEOUT` no pierde lo hecho.

Antes de encolar mucho, `sbatch --test-only ...` estima el arranque sin encolar.

### 7. Seguir y reintentar

```bash
ssh helvetios 'squeue --me --start'
ssh helvetios 'cd PROYECTO && bash scripts/estado.sh'          # totales, lotes incompletos y el comando para relanzarlos
ssh helvetios 'cd PROYECTO && bash scripts/estado.sh fallos'   # final del log de cada tile fallido
ssh helvetios 'sacct -X -j JOBID -o JobID%20,State,Elapsed,ExitCode; seff JOBID_1'
```

Relanzar un lote es seguro y reintenta sus fallidos y pendientes. Un tile que falla siempre igual es un problema del programa o del dato: mirar su log antes de relanzar.

### 8. Traer resultados

```bash
rsync -av --partial helvetios:PROYECTO/salida/ /ruta/local/salida/
```

Las carpetas `salida/.tmp_*` son copias interrumpidas: se pueden ignorar (`--exclude '.tmp_*'`).

## Errores típicos de este flujo

- **Nodo con CPU al 100 % pero lento, o `seff` con eficiencia muy baja:** hilos de más (alguna biblioteca ignora `OMP_NUM_THREADS`) o E/S desde el /home. Bajar `P`, o confirmar que la entrada se copió al /scratch.
- **`OUT_OF_MEMORY` o nodos que mueren:** `P × R` supera la RAM pedida. En Helvetios, verificar primero que se pidió `--mem=0` (o suficiente); después, bajar `P`.
- **Todos los tiles quedan "pendientes" sin correr:** `SEG_TILE` mayor que el tiempo del job; bajarlo o usar la partición larga (`batch` en Helvetios, `multi` en Serafín).
- **Mensajes `(PDAL Error) Can't load library ... libpdal_plugin_reader_hdf.so`:** son plugins de HDF que el paquete de conda-forge no puede cargar. No afectan a LAS/LAZ; ignorarlos.
