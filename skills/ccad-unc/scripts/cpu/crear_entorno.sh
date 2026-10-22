#!/usr/bin/env bash
# Crea (o actualiza) el entorno conda del proyecto y lo empaqueta en un .tar para correrlo desde el /scratch.
# Se corre EN LA CABECERA (los nodos de cómputo no tienen internet), desde la carpeta del proyecto:
#
#   bash scripts/crear_entorno.sh                 # usa scripts/environment.yml, entorno "geo"
#   bash scripts/crear_entorno.sh otro.yml otro   # archivo y nombre a elección
#
# Por qué empaquetar: el /home es NFS y cargar miles de .so desde ahí en un nodo es lentísimo
# (Germán midió 710 s para `import torch`). Un .tar se lee de corrido y en el /scratch local carga rápido.
# Volver a correr este script cada vez que cambie environment.yml.
set -euo pipefail

YML=${1:-scripts/environment.yml}
NOMBRE=${2:-geo}
MF=${MINIFORGE:-$HOME/miniforge3}
SALIDA=${ENTORNO_TAR:-$PWD/entorno/$NOMBRE.tar}

[ -f "$YML" ] || { echo "no encuentro $YML (correr desde la carpeta del proyecto)" >&2; exit 1; }

if [ ! -x "$MF/bin/conda" ]; then
    echo "Instalando Miniforge en $MF (conda-forge, sin el canal defaults de Anaconda)"
    instalador=$(mktemp --suffix=.sh)
    curl -fsSL -o "$instalador" \
        https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
    bash "$instalador" -b -p "$MF"
    rm -f "$instalador"
fi
CONDA="$MF/bin/conda"
# mamba (viene con Miniforge) resuelve más rápido y con menos memoria que conda.
# -y: sin preguntas. El aviso de libmamba sobre "package scripts" es informativo (paquetes de conda-forge).
SOLVER="$MF/bin/mamba"; [ -x "$SOLVER" ] || SOLVER="$CONDA"

"$SOLVER" install -y -n base -c conda-forge conda-pack >/dev/null

if "$CONDA" env list | awk '{print $1}' | grep -qx "$NOMBRE"; then
    echo "Actualizando el entorno $NOMBRE desde $YML"
    if [ "$SOLVER" = "$CONDA" ]; then "$CONDA" env update -n "$NOMBRE" -f "$YML" --prune
    else "$SOLVER" env update -y -n "$NOMBRE" -f "$YML" --prune; fi
else
    echo "Creando el entorno $NOMBRE desde $YML"
    "$SOLVER" env create -y -n "$NOMBRE" -f "$YML"
fi

mkdir -p "$(dirname "$SALIDA")"
echo "Empaquetando en $SALIDA"
"$MF/bin/conda-pack" -p "$MF/envs/$NOMBRE" -o "$SALIDA.tmp.tar" --ignore-editable-packages --force -q
mv "$SALIDA.tmp.tar" "$SALIDA"
ls -lh "$SALIDA"

# Prueba rápida en la cabecera (liviana: sólo imports).
"$MF/envs/$NOMBRE/bin/python" -c "import pdal, rasterio, laspy, numpy; from osgeo import gdal; \
print('pdal', pdal.__version__, '| gdal', gdal.__version__, '| rasterio', rasterio.__version__)"

echo "Listo. Para liberar cuota en el /home: $CONDA clean -a -y"
