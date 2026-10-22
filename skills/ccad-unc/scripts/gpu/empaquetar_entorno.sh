#!/usr/bin/env bash
# Empaqueta el entorno del tuneo en un solo .tar para correrlo desde el /scratch local de cada nodo.
# Se corre en la cabecera de Mendieta, desde la carpeta del proyecto, después de crear el .venv con uv
# (ver references/gpu-mendieta.md) y cada vez que cambie .venv:
#
#   bash scripts/empaquetar_entorno.sh
#
# Por qué: en un nodo de cómputo, `import torch` desde el /home (NFS) tardó 710 s: cargar ~3 GB de .so por red es
# una lluvia de lecturas chicas. Un .tar se lee de corrido y en el /scratch (SSD local) las bibliotecas cargan rápido.
#
# El paquete es UN árbol de Python: el CPython independiente de uv (relocalizable, no depende de Miniconda) con el
# site-packages de .venv adentro, así los .pth se procesan como siempre. Lo descomprime scripts/entorno_scratch.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

PY_DIR=$(ls -d "$HOME"/.local/share/uv/python/cpython-3.13.*-linux-x86_64-gnu | sort -V | tail -1)
SITE=.venv/lib/python3.13/site-packages
SALIDA=entorno/py313.tar
[ -x "$PY_DIR/bin/python3.13" ] || { echo "falta el Python de uv en $PY_DIR (ver references/gpu-mendieta.md)" >&2; exit 1; }
[ -d "$SITE" ] || { echo "falta $SITE (ver references/gpu-mendieta.md)" >&2; exit 1; }

mkdir -p entorno
echo "Python: $PY_DIR"
echo "bibliotecas: $SITE ($(du -sh "$SITE" | cut -f1))"
# las rutas de site-packages se reubican dentro del árbol de Python; el resto del árbol va tal cual
tar -cf "$SALIDA.tmp" --exclude __pycache__ \
    -C "$PY_DIR" . \
    -C "$PWD/.venv/lib/python3.13" --transform 's,^site-packages,./lib/python3.13/site-packages,' site-packages
mv "$SALIDA.tmp" "$SALIDA"
ls -lh "$SALIDA"
