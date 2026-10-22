# Se usa con `source` dentro de un sbatch: descomprime el entorno empaquetado por crear_entorno.sh
# en el /scratch local del nodo y lo activa. Slurm borra el /scratch al terminar el job.
# Necesita PROY (carpeta del proyecto) y SCRATCH_DIR (directorio del job en el /scratch).
# Misma idea que scripts/gpu/entorno_scratch.sh, adaptada a conda-pack.
ENTORNO_TAR=${ENTORNO_TAR:-$PROY/entorno/geo.tar}
ENTORNO_DIR=$SCRATCH_DIR/env
[ -f "$ENTORNO_TAR" ] || { echo "falta $ENTORNO_TAR: correr scripts/crear_entorno.sh en la cabecera" >&2; exit 1; }
mkdir -p "$ENTORNO_DIR"
_t0=$(date +%s)
tar -xf "$ENTORNO_TAR" -C "$ENTORNO_DIR"
# El activate de conda-pack usa variables sin definir: desactivar `set -u` mientras corre.
set +u
source "$ENTORNO_DIR/bin/activate"
conda-unpack
set -u
export PYTHONNOUSERSITE=1
export GDAL_DATA=${GDAL_DATA:-$ENTORNO_DIR/share/gdal}
export PROJ_DATA=${PROJ_DATA:-$ENTORNO_DIR/share/proj}
hash -r
echo "entorno en $ENTORNO_DIR ($(du -sh "$ENTORNO_DIR" | cut -f1)), listo en $(( $(date +%s) - _t0 )) s; python: $(command -v python3)"
