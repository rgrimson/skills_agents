# Skill `ccad-unc`

## Qué es

Una skill de Claude Code para trabajar con los clusters de **UNC Supercómputo (CCAD, Universidad Nacional de Córdoba)**: Mendieta (GPU A30), Serafín, Mulatona y Eulogia. Le da a Claude el contexto para:

- elegir cluster y partición según el trabajo: GPU en Mendieta, CPU en Serafín, pruebas en Mulatona;
- conectarse por SSH y usar Slurm (`sbatch`, job arrays, `squeue`, `sacct`, `seff`);
- preparar entornos de Python que carguen rápido en los nodos (PyTorch con uv, o PDAL/GDAL con conda-pack);
- entrenar en GPU con checkpoints y retoma, o procesar miles de archivos (tiles LiDAR, rásters) en lotes que llenan nodos de CPU;
- mover archivos (`rsync`) y traer resultados;
- diagnosticar errores típicos (`TIMEOUT`, `OUT_OF_MEMORY`, `DependencyNeverSatisfied`, imports lentos, nodos subutilizados).

Contenido:

| Archivo | Qué tiene |
|---|---|
| `SKILL.md` | Lo común: elegir cluster, reglas, almacenamiento, conexión, Slurm, errores, seguridad. Es lo que Claude carga al usar la skill, y desde ahí deriva al flujo que corresponde. |
| `references/gpu-mendieta.md` | Flujo con GPU en Mendieta: entorno con uv, prueba, sbatch, checkpoints y retoma. |
| `references/lecciones-mendieta.md` | Lo aprendido en la práctica y que no está en la wiki (entorno en `/scratch`, `set -u`, `singleton`, retoma en GPU, parar a tiempo, SIGTERM, etc.). |
| `references/cpu-tiles.md` | Flujo por tiles en CPU en Serafín y Mulatona: medir, dimensionar, lotes, job arrays, reintentos. |
| `references/wiki.md` | Resumen, página por página, de la wiki oficial (https://wiki.ccad.unc.edu.ar/). |
| `scripts/gpu/` | Empaquetar y descomprimir el entorno de uv, plantilla sbatch de GPU, prueba del entorno. |
| `scripts/cpu/` | Crear y empaquetar el entorno conda, armar lotes, medir, job array por lotes, envoltorio por tile, estado; ejemplo con PDAL. |

Los scripts de `scripts/gpu/` o `scripts/cpu/` se copian a `PROYECTO/scripts/` en el cluster y se corren desde la carpeta del proyecto.

## Cómo instalarla

La carpeta de la skill es `ccad-unc/` (la que contiene este README y `SKILL.md`). Claude Code solo busca skills directamente dentro de `.claude/skills/`, en el proyecto o en tu home. Ejemplos con el repo `skills_agents`, donde la skill está en `skills/ccad-unc`.

### Caso 1: proyecto con contenedor que ya existe (sin rebuild)

No se toca el contenedor ni su configuración. En la terminal, en la raíz del proyecto:

```bash
mkdir -p .claude/skills
git clone git@github.com:<usuario>/skills_agents.git .claude/skills_agents
ln -s ../skills_agents/skills/ccad-unc .claude/skills/ccad-unc
printf ".claude/skills_agents/\n.claude/skills/ccad-unc\n" >> .gitignore
```

Para actualizar cuando la skill cambie: `git -C .claude/skills_agents pull`.

Alternativa sin enlace: copiar la carpeta (`cp -r .../skills/ccad-unc .claude/skills/`). Queda versionada con el proyecto, pero hay que recopiarla a mano en cada cambio.

### Caso 2: proyecto nuevo (se arma el devcontainer desde cero)

En `.devcontainer/devcontainer.json`:

```json
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/node:2.1.0": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
  },
  "mounts": ["source=claude-config,target=/home/vscode/.claude,type=volume"],
  "postCreateCommand": "mkdir -p ~/.claude/skills && (git clone git@github.com:<usuario>/skills_agents.git ~/skills_agents || git -C ~/skills_agents pull) && ln -sfn ~/skills_agents/skills/ccad-unc ~/.claude/skills/ccad-unc"
}
```

Después, `Dev Containers: Reopen in Container`. La skill queda en `~/.claude/skills` y vale para todos los proyectos de ese contenedor. El volumen `claude-config` conserva la memoria de Claude entre rebuilds. Para actualizar: `git -C ~/skills_agents pull`.

### Caso 3: sin contenedor (máquina propia)

```bash
git clone git@github.com:<usuario>/skills_agents.git ~/skills_agents
mkdir -p ~/.claude/skills
ln -s ~/skills_agents/skills/ccad-unc ~/.claude/skills/ccad-unc
```

### Verificar la instalación

```bash
ls -la .claude/skills/        # o ~/.claude/skills/ según el caso
```

Debe aparecer `ccad-unc -> ...` apuntando a una carpeta que exista. Después, en una sesión nueva de Claude Code, `ccad-unc` figura entre las skills disponibles.

Notas:
- Si el repo `skills_agents` es privado, el clon por SSH necesita tu agente SSH. VS Code lo reenvía al contenedor por defecto.
- Un rebuild borra el home del contenedor (`~/.claude`, incluida la memoria de Claude) si no hay volumen montado. Con el Caso 1 la skill sobrevive igual, porque está dentro del proyecto.

## Cómo usarla en una sesión de chat

1. **Invocarla.** Escribí `/ccad-unc`, o pedí algo del cluster con palabras normales ("cómo encolo un job en Mendieta", "revisá cómo viene mi job"); Claude carga la skill solo cuando el tema coincide.
2. **Conexión.** Claude se conecta con tu agente SSH (`ssh -o BatchMode=yes <usuario>@<cluster>.ccad.unc.edu.ar`, o tus alias de `~/.ssh/config`). La clave privada nunca se le pide ni se copia. Si el agente no está disponible, no puede conectarse.
3. **Qué hace sin preguntar:** comandos de lectura (`squeue`, `sacct`, `sinfo`, leer logs y archivos de resultados, `sbatch --test-only`).
4. **Qué te pregunta antes:** cualquier cosa que modifique el cluster: encolar (`sbatch`), cancelar (`scancel`), cambiar jobs (`scontrol update`), subir o sobrescribir archivos.
5. **Pedidos típicos:**
   - "Preparame un sbatch para entrenar X en una GPU" (usa `scripts/gpu/plantilla-sbatch.sh`).
   - "Tengo 400 tiles LAZ para procesar con este script, armame la corrida en Serafín" (usa `scripts/cpu/`).
   - "Estimá cuándo arranca este job en multi" (`squeue --me --start`).
   - "El job terminó en TIMEOUT, ¿por qué?" (revisa log y `sacct`).
   - "Bajá los resultados a mi máquina" (`rsync`).
6. **Seguimiento periódico:** se puede combinar con `/loop` para revisar un job cada cierto tiempo, y avisar solo si algo falla o termina.

Antes del primer job de GPU conviene pedirle a Claude que lea `references/lecciones-mendieta.md`: cada punto costó al menos un job fallido.

## Confirmación obligatoria para ssh y rsync

La skill le pide a Claude confirmar antes de encolar, cancelar o borrar, pero es una instrucción, no un candado. Para que Claude Code pida aprobación antes de cada comando hacia el cluster, en `~/.claude/settings.json` (o `.claude/settings.json` del proyecto):

```json
{
  "permissions": {
    "ask": ["Bash(ssh:*)", "Bash(rsync:*)", "Bash(scp:*)"]
  }
}
```

## Créditos

Skill original (flujo de GPU, lecciones de Mendieta, resumen de la wiki, reglas de seguridad): Germán Rosati.
Flujo de CPU por tiles y reorganización en núcleo común más referencias: Rafael Grimson.
