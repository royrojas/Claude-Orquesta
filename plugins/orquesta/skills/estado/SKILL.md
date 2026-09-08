---
name: estado
description: Muestra el estado de orquesta en este proyecto - qué modelo tiene asignado cada trabajador (config efectiva y de dónde sale), el PLAN y sus tareas abiertas, si graphify y las carpetas de Obsidian están disponibles, y las delegaciones por modelo. Usalo cuando el usuario pregunte qué modelos usa la orquestación, cómo cambiar el modelo de un trabajador, cómo va el plan, o para diagnosticar por qué una compuerta bloqueó algo.
argument-hint: [sin argumentos]
allowed-tools: Bash(pwsh *) PowerShell(pwsh *)
disable-model-invocation: true
---

# Estado de orquesta

!`pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Show-Estado.ps1"`

Presentale al usuario lo de arriba tal cual (es Markdown), y agregá debajo, en máximo 8 líneas, lo que aplique:

- **Cambiar modelos**: copiar solo las claves a cambiar a `.claude/orquesta.json` (proyecto) o `~/.claude/orquesta.json` (usuario). Ejemplo mínimo:
  ```json
  { "trabajadores": { "implementador": { "modelo": "opus" }, "revisor": { "modelo": "fable" } } }
  ```
  Valores: `haiku`, `sonnet`, `opus`, `fable`, `inherit` o un ID completo. Los defaults completos están en `${CLAUDE_PLUGIN_ROOT}/config/orquesta.defaults.json`.
- **Cambiar el arquitecto**: es el modelo de la sesión: `claude --model fable` o `/model fable`. La config solo lo declara para avisar si no coincide.
- **Compuertas**: `compuertas.*` en la misma config, o `ORQUESTA_GATES=0` en el entorno para apagarlas en una sesión. `estado: pausado` en el PLAN las relaja temporalmente.
- Si hay PLAN `en-ejecucion` con tareas abiertas, sugerí `/orquesta:arquitecto` para reanudar; si está `cerrado`, recordá archivarlo antes de un plan nuevo.
