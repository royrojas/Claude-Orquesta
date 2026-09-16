---
name: costos
description: Muestra cuánto costó la orquestación de este proyecto, medido y no estimado - requests, contexto, tokens de entrada, caché y salida (con thinking) del arquitecto y de cada subagente de Claude, leídos del `usage` real de los transcripts de Claude Code, más los tokens de Codex de la bitácora, valorados con `costos.tarifas`. Usalo al cerrar un PLAN, cuando el usuario pregunte cuánto gastó o consumió la orquestación, qué modelo o actor gastó más, o por qué el arquitecto consume tanto.
argument-hint: [-Sesion <id>, opcional]
allowed-tools: Bash(pwsh *), PowerShell(pwsh *)
disable-model-invocation: true
---

# Costos de orquesta

!`pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Show-Costos.ps1" $ARGUMENTS`

Presentale al usuario lo de arriba tal cual (es Markdown) y agregá debajo, en máximo 6 líneas, solo lo que aplique:

- **Qué mueve la aguja**: el costo del arquitecto es requests × contexto (cada tool call relee todo el contexto por caché) más la salida (thinking incluido). Si hay más de ~60 requests o el contexto pasa de 300k, decilo y recordá las reglas de "Economía de contexto" del skill arquitecto: registro con `Marcar-Tarea.ps1`, contratos vía cartógrafo, sin polling, sin skills ajenas.
- **Arranques en frío**: si la salida los marca, explicá en una línea que reanudar una sesión larga tras más de una hora o cambiar de modelo re-escribe toda la caché, y que retro, memoria y tareas laterales van en sesión nueva o subagente.
- **Tarifas**: si un modelo salió con tarifa asumida, indicá dónde agregarla (`costos.tarifas` en `.claude/orquesta.json`). Con suscripción los dólares son referencia; los tokens sí cuentan contra la cuota.
- Si no encontró sesiones, sugerí `-Sesion <id>` (el id es el nombre del transcript bajo `~/.claude/projects/<proyecto>/`).
