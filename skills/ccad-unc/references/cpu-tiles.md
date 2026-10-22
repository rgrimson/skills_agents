# Flujo de trabajo por tiles en CPU (Serafín y Mulatona)

Para muchos archivos independientes que se procesan igual: nubes LiDAR (LAS/LAZ), rásters, imágenes.
Producción en **Serafín**, mediciones y pruebas en **Mulatona**.
Scripts en `scripts/cpu/`; se copian a `PROYECTO/scripts/` en el cluster.
En los ejemplos, `serafin` y `mulatona` son alias de `~/.ssh/config` (ver SKILL.md, "Conexión"); si no existen, usar `USUARIO@serafin.ccad.unc.edu.ar`.

## Por qué así

- **En Serafín el job mínimo es un nodo entero (64 cores)** y Slurm cobra lo reservado: un tile por job desperdicia 63 cores. Un job = un lote de tiles corriendo en paralelo dentro del nodo, con `xargs -P` y un hilo por proceso.
- **Mulatona acepta jobs de 1 core:** sirve para medir tiempo y memoria por tile sin ocupar un nodo. Es más lenta que Serafín, así que sus tiempos son una cota superior.
- Los dos tienen AVX2: el mismo entorno empaquetado corre en ambos.
- Cada tile terminado queda marcado y copiado al /home enseguida: un `TIMEOUT` no pierde lo hecho y relanzar un lote es seguro.

## Antes de empezar: ¿conviene el cluster?

Estimar primero cuánto pesa el cálculo frente a la transferencia. Referencia medida (2026-10, LiDAR del Matanza-Riachuelo, MDT de 1 m por IDW con PDAL): **~35 s de un core por GB de LAS** en Mulatona; en Serafín, 6 tiles de ~250 MB en un job de 21 s. Para 100 GB eso es ~1 hora-core, un par de minutos de un nodo de Serafín, mientras que subir 100 GB lleva horas.

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
rsync -av scripts/cpu/ serafin:PROYECTO/scripts/                # los de esta skill
rsync -av procesar_tile.py serafin:PROYECTO/
rsync -av --partial --info=progress2 /ruta/local/tiles/ serafin:PROYECTO/entrada/
```

- Antes de subir mucho, ver espacio y cuota: `ssh serafin 'df -h ~; quota -s 2>/dev/null'`. Si no está claro el límite del /home, preguntar a soporte antes de subir decenas de GB.
- Medir la velocidad primero (100 GB a 68 Mbit/s son ~3 h; a 20 Mbit/s, ~11 h): `head -c 500M /dev/zero | ssh serafin 'cat > /dev/null'`. Una copia larga va en `tmux` o `nohup` en la máquina local. `--partial` permite retomarla.
- Verificar al final: cantidad de archivos y bytes iguales en origen y destino (`find ... | wc -l`, `du -sb`).
- El cluster no tiene git-lfs: copiar el árbol de trabajo, no clonar un repo con archivos LFS.

### 2. Entorno (en la cabecera)

```bash
ssh serafin 'cd PROYECTO && bash scripts/crear_entorno.sh'
```

Instala Miniforge en `~/miniforge3` si falta (la wiki recomienda un entorno propio en el home), crea el entorno con mamba desde `scripts/environment.yml` (editarlo según el proyecto) y lo empaqueta con conda-pack en `entorno/geo.tar` (~1,5 GB con el `environment.yml` incluido; en el nodo se descomprime en unos segundos). Los jobs lo descomprimen en el /scratch (`entorno_scratch.sh`) porque cargar bibliotecas desde el /home (NFS) es muy lento. **Volver a correrlo cada vez que cambie `environment.yml`.** Los /home de Serafín y Mulatona son independientes: hay que hacerlo en los dos.

### 3. Armar los lotes

```bash
ssh serafin 'cd PROYECTO && bash scripts/armar_lotes.sh 40'
```

Lista los tiles de `entrada/`, verifica nombres únicos y escribe `lotes/todos.txt` y un archivo por lote. Para una medición alcanza con cualquier número; el definitivo sale del paso 5.

### 4. Medir (Mulatona, después Serafín)

```bash
ssh mulatona 'cd PROYECTO && mkdir -p logs && sbatch scripts/medir_tile.sbatch'
ssh mulatona 'cd PROYECTO && sbatch --export=ALL,N=6,P=3 -c 3 scripts/medir_tile.sbatch'   # contención
```

El final del log tiene, por tile, segundos, RAM máxima (MB) y segundos por GB de entrada. (Los nodos de Mulatona no tienen `/usr/bin/time`; la RAM la mide entonces el Python del entorno.) La segunda variante muestra si correr varios a la vez los frena (por disco o memoria). Después, confirmar en Serafín con **un solo lote** en `short`: `sbatch --array=1 scripts/lote_tiles.sbatch` y mirar `seff` del job.

### 5. Dimensionar

Con `T` = segundos por tile medidos en Serafín (o en Mulatona, más conservador) y `R` = RAM máxima por tile:

- **Procesos por nodo** `P = min(64, 230 GB / R)`. Si `P < 64`, pasar `--export=ALL,P=...`: menos procesos que cores es mejor que quedarse sin memoria.
- **Tiles por lote** para entrar en `short` (1 h, con 5 min de margen): el nodo procesa en tandas de `P` tiles, y en 3000 s entran `floor(3000 / T)` tandas, así que `tiles por lote = P × floor(3000 / T)`. `short` arranca mucho antes que `multi`, así que conviene que cada lote dure ~50 min. Si un tile solo tarda más de ~40 min, usar `multi` (`--partition=multi --time=0-12:00 --export=ALL,MARGEN_SEG=900`) y recalcular con el tiempo pedido.
- **`SEG_TILE`** = el máximo medido, con un poco de margen: un tile no se empieza si no queda ese tiempo, y queda pendiente para el próximo envío.
- **El lote tiene que caber en el /scratch** (1 TB en Serafín) si se copia la entrada; el script lo verifica y, si no entra, lee del /home.
- Horas-core totales ≈ `tiles × T / 3600`; con `P` procesos por nodo de 64 cores se reservan `64 / P` veces más.

Ejemplos con 394 tiles de ~250 MB:
- Medido (MDT por IDW): `T` ≈ 9 s en Mulatona, menos en Serafín → todos en **un solo lote y un solo nodo**, unos minutos. Con tiles tan rápidos, el costo fijo (descomprimir el entorno y copiar la entrada al /scratch) pesa más que el cálculo: no partir en lotes chicos.
- Pipeline pesado, `T` = 300 s, `R` = 3 GB → `P` = 64 y hasta 64 × 10 = 640 tiles por lote: un nodo, 7 tandas de 300 s (~35 min).
- `T` = 1800 s → una tanda por hora: lotes de 64 tiles, 7 lotes, y con `%4` dos rondas de una hora.

### 6. Lanzar

```bash
ssh serafin 'cd PROYECTO && bash scripts/armar_lotes.sh N -f && mkdir -p logs && \
  sbatch --array=1-NLOTES%4 --export=ALL,SEG_TILE=...,P=... scripts/lote_tiles.sbatch'
```

`lote_tiles.sbatch` hace, en cada nodo: calcula la hora de corte, saltea los tiles ya terminados, descomprime el entorno en el /scratch, copia la entrada del lote, corre `procesar_tile.sh` con `xargs -P` (un hilo por proceso: fija `OMP_NUM_THREADS=1`, `GDAL_NUM_THREADS=1`, etc.) y resume ok/fallidos/pendientes al final. Cada tile terminado se copia al /home enseguida, así que un `TIMEOUT` no pierde lo hecho.

Antes de encolar mucho, `sbatch --test-only ...` estima el arranque sin encolar.

### 7. Seguir y reintentar

```bash
ssh serafin 'squeue --me --start'
ssh serafin 'cd PROYECTO && bash scripts/estado.sh'          # totales, lotes incompletos y el comando para relanzarlos
ssh serafin 'cd PROYECTO && bash scripts/estado.sh fallos'   # final del log de cada tile fallido
ssh serafin 'sacct -X -j JOBID -o JobID%20,State,Elapsed,ExitCode; seff JOBID_1'
```

Relanzar un lote es seguro y reintenta sus fallidos y pendientes. Un tile que falla siempre igual es un problema del programa o del dato: mirar su log antes de relanzar.

### 8. Traer resultados

```bash
rsync -av --partial serafin:PROYECTO/salida/ /ruta/local/salida/
```

Las carpetas `salida/.tmp_*` son copias interrumpidas: se pueden ignorar (`--exclude '.tmp_*'`).

## Errores típicos de este flujo

- **Nodo con CPU al 100 % pero lento, o `seff` con eficiencia muy baja:** hilos de más (alguna biblioteca ignora `OMP_NUM_THREADS`) o E/S desde el /home. Bajar `P`, o confirmar que la entrada se copió al /scratch.
- **`OUT_OF_MEMORY` o nodos que mueren:** `P × R` supera la RAM. Bajar `P`.
- **Todos los tiles quedan "pendientes" sin correr:** `SEG_TILE` mayor que el tiempo del job; bajarlo o usar `multi`.
- **Mensajes `(PDAL Error) Can't load library ... libpdal_plugin_reader_hdf.so`:** son plugins de HDF que el paquete de conda-forge no puede cargar. No afectan a LAS/LAZ; ignorarlos.
