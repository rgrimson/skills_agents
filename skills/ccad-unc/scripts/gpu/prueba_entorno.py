#!/usr/bin/env python3
"""Prueba del entorno en un nodo de GPU de Mendieta. La lanza prueba_mendieta.sbatch.

Imprime la hora de cada etapa (sin buffer) para ver dónde se traba algo: el import de torch,
la inicialización de CUDA o el cálculo. Si algo se cuelga, faulthandler vuelca la pila cada 60 s.
"""
import faulthandler
import os
import sys
import time

faulthandler.dump_traceback_later(60, repeat=True)
T0 = time.time()


def etapa(msg):
    print(f"[{time.time() - T0:7.1f} s] {msg}", flush=True)


etapa(f"python {sys.version.split()[0]} en {sys.executable}")
etapa(f"CUDA_VISIBLE_DEVICES={os.environ.get('CUDA_VISIBLE_DEVICES')}, OMP_NUM_THREADS={os.environ.get('OMP_NUM_THREADS')}")

import torch  # noqa: E402  (se mide cuánto tarda)

etapa(f"torch {torch.__version__} importado (CUDA de compilación {torch.version.cuda})")

if not torch.cuda.is_available():
    etapa("ERROR: torch no ve ninguna GPU")
    sys.exit(1)

n = torch.cuda.device_count()
for i in range(n):
    p = torch.cuda.get_device_properties(i)
    etapa(f"GPU {i}: {p.name}, {p.total_memory / 2**30:.1f} GB, sm_{p.major}{p.minor}")

dev = torch.device("cuda:0")
a = torch.randn(4096, 4096, device=dev)
b = torch.randn(4096, 4096, device=dev)
torch.cuda.synchronize()
etapa("tensores en la GPU")

reps = 20
t = time.time()
for _ in range(reps):
    a @ b
torch.cuda.synchronize()
seg = time.time() - t
etapa(f"matmul fp32 4096²: {2 * 4096**3 * reps / seg / 1e12:.1f} TFLOP/s")

faulthandler.cancel_dump_traceback_later()
etapa("prueba terminada")
