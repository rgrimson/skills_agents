# Se usa con `source` dentro de un sbatch de Mendieta (desde la carpeta del proyecto): descomprime el entorno empaquetado por
# empaquetar_entorno.sh en el /scratch local del nodo y lo pone primero en el PATH. Slurm borra el /scratch al
# terminar el job. Ver empaquetar_entorno.sh para el porqué.
ENTORNO_TAR=${ENTORNO_TAR:-$PWD/entorno/py313.tar}
ENTORNO_DIR=/scratch/$USER/$SLURM_JOB_ID/py
[ -f "$ENTORNO_TAR" ] || { echo "falta $ENTORNO_TAR: correr scripts/empaquetar_entorno.sh en la cabecera" >&2; exit 1; }
mkdir -p "$ENTORNO_DIR"
_t0=$(date +%s)
tar -xf "$ENTORNO_TAR" -C "$ENTORNO_DIR"
export PATH="$ENTORNO_DIR/bin:$PATH" PYTHONNOUSERSITE=1
hash -r
echo "entorno en $ENTORNO_DIR ($(du -sh "$ENTORNO_DIR" | cut -f1)), copiado en $(( $(date +%s) - _t0 )) s; python: $(command -v python3)"
