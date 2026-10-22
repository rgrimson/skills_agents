#!/usr/bin/env bash
# Procesa UN tile (ver references/cpu-tiles.md). Lo llama lote_tiles.sbatch (vía xargs, muchos en paralelo) o medir_tile.sbatch.
#   procesar_tile.sh RUTA_RELATIVA_EN_entrada/
#
# Variables que tiene que recibir del sbatch:
#   PROY         carpeta del proyecto en el /home
#   SCRATCH_DIR  directorio del job en el /scratch local
#   CMD_TILE     comando del usuario; se llama como: $CMD_TILE ARCHIVO_ENTRADA DIRECTORIO_SALIDA
#   HASTA_EPOCH  hora Unix a la que el job tiene que haber terminado (ya descontado el margen)
#   SEG_TILE     tiempo máximo esperado de un tile; si no queda ese tiempo, el tile no se empieza
# Opcionales (medir_tile.sbatch las usa para no mezclar la prueba con la corrida real):
#   ESTADO_DIR, SALIDA_DIR, LOGS_TILES   por defecto $PROY/estado, $PROY/salida, $PROY/logs/tiles
#
# Garantías:
#   - Idempotente: si estado/ok/NOMBRE existe, no hace nada. Relanzar un lote sólo procesa lo pendiente.
#   - La salida aparece en salida/NOMBRE/ entera o no aparece (se copia a un temporal y se renombra).
#   - Un tile que falla deja estado/fallo/NOMBRE y su log; los demás siguen.
#   - Siempre sale con 0, para que xargs no corte el lote. El resumen está en estado/.
set -uo pipefail

REL=$1
NOMBRE=$(basename "$REL"); NOMBRE=${NOMBRE%.*}
ESTADO_DIR=${ESTADO_DIR:-$PROY/estado}
SALIDA_DIR=${SALIDA_DIR:-$PROY/salida}
LOGS_TILES=${LOGS_TILES:-$PROY/logs/tiles}
OK="$ESTADO_DIR/ok/$NOMBRE"
FALLO="$ESTADO_DIR/fallo/$NOMBRE"
LOG="$LOGS_TILES/$NOMBRE.log"

[ -e "$OK" ] && exit 0

AHORA=$(date +%s)
if (( AHORA + SEG_TILE > HASTA_EPOCH )); then
    echo "$(date '+%F %T') $NOMBRE: no queda tiempo, queda pendiente"
    exit 0
fi

ENT="$SCRATCH_DIR/in/$REL"
[ -f "$ENT" ] || ENT="$PROY/entrada/$REL"     # si no se copió al /scratch, se lee del /home
SAL="$SCRATCH_DIR/out/$NOMBRE"
rm -rf "$SAL"; mkdir -p "$SAL"

read -ra CMD <<< "$CMD_TILE"
# Medir la RAM máxima del tile. Los nodos de Mulatona no tienen /usr/bin/time (2026-10): en ese caso
# se usa el Python del entorno, que escribe la misma línea que `time -v` para que medir_tile.sbatch la lea.
if [ -x /usr/bin/time ]; then
    TIEMPO=(/usr/bin/time -v)
else
    TIEMPO=(python3 -c 'import resource, subprocess, sys
r = subprocess.call(sys.argv[1:])
kb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
print(f"\tMaximum resident set size (kbytes): {kb}", file=sys.stderr)
sys.exit(r if r >= 0 else 128 - r)')
fi

T0=$(date +%s)
{
    echo "== $(date '+%F %T') $NOMBRE en $(hostname), job ${SLURM_JOB_ID:-?}"
    echo "== entrada: $ENT"
} > "$LOG"
timeout --signal=TERM --kill-after=60 $(( HASTA_EPOCH - AHORA )) \
    "${TIEMPO[@]}" "${CMD[@]}" "$ENT" "$SAL" >> "$LOG" 2>&1
RC=$?
SEG=$(( $(date +%s) - T0 ))

if [ "$RC" -eq 0 ]; then
    DEST="$SALIDA_DIR/$NOMBRE"
    TMP="$SALIDA_DIR/.tmp_$NOMBRE"
    rm -rf "$TMP"
    if cp -r "$SAL" "$TMP" && rm -rf "$DEST" && mv "$TMP" "$DEST"; then
        echo "$SEG" > "$OK"
        rm -f "$FALLO"
        echo "$(date '+%F %T') $NOMBRE: ok en $SEG s"
    else
        echo "copia de la salida al /home falló" >> "$LOG"
        echo "copia" > "$FALLO"
        echo "$(date '+%F %T') $NOMBRE: FALLÓ la copia al /home"
    fi
else
    [ "$RC" -eq 124 ] && MOTIVO="plazo" || MOTIVO="código $RC"
    echo "$MOTIVO" > "$FALLO"
    echo "$(date '+%F %T') $NOMBRE: FALLÓ ($MOTIVO) en $SEG s, ver $LOG"
fi

# Liberar el /scratch: la entrada copiada y la salida ya no hacen falta.
rm -rf "$SAL"
[ "$ENT" = "$SCRATCH_DIR/in/$REL" ] && rm -f "$ENT"
exit 0
