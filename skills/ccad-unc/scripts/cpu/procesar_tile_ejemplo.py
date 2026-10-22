#!/usr/bin/env python3
"""Ejemplo de programa por tile: MDT de 1 m a partir de los puntos de suelo de un tile LAS/LAZ.

Contrato que espera procesar_tile.sh (cualquier programa que lo cumpla sirve):
  - se llama como:  procesar_tile.py ARCHIVO_ENTRADA DIRECTORIO_SALIDA
  - escribe SOLO dentro de DIRECTORIO_SALIDA (ya existe y está vacío, en el /scratch);
  - usa un solo hilo (el paralelismo lo da xargs con muchos tiles a la vez);
  - sale con 0 si todo anduvo; con otro código si falló (el tile queda en estado/fallo/).

Copiarlo como procesar_tile.py en la carpeta del proyecto y reemplazar el pipeline por el real.
"""
import json
import sys
import time
from pathlib import Path

import pdal


def main(entrada: str, salida: str) -> int:
    t0 = time.time()
    nombre = Path(entrada).stem
    tif = Path(salida) / f"{nombre}_mdt.tif"

    pipeline = [
        {"type": "readers.las", "filename": entrada},
        {"type": "filters.range", "limits": "Classification[2:2]"},   # sólo suelo
        {
            "type": "writers.gdal",
            "filename": str(tif),
            "resolution": 1.0,
            "output_type": "idw",
            "gdaldriver": "GTiff",
            "gdalopts": "COMPRESS=DEFLATE,PREDICTOR=3,TILED=YES",
            "data_type": "float32",
            "nodata": -9999,
        },
    ]
    p = pdal.Pipeline(json.dumps(pipeline))
    n = p.execute()
    print(f"{nombre}: {n} puntos de suelo, {tif.name} en {time.time() - t0:.1f} s", flush=True)
    if n == 0:
        print("sin puntos de suelo: revisar la clasificación del tile", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("uso: procesar_tile.py ARCHIVO_ENTRADA DIRECTORIO_SALIDA")
    sys.exit(main(sys.argv[1], sys.argv[2]))
