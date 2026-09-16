---
name: doctor
description: Diagnostica el entorno de orquesta - PowerShell 7 y pwsh en PATH, hooks y scripts del plugin, config efectiva y motores de los trabajadores, Codex CLI y su login (si algún trabajador usa codex), plugin oficial de OpenAI, graphify, Obsidian y git del proyecto. Usalo tras instalar el plugin, cuando una compuerta o Invoke-Codex falle sin motivo claro, o cuando el usuario pregunte "¿está todo bien configurado?".
argument-hint: [sin argumentos]
allowed-tools: Bash(pwsh *) PowerShell(pwsh *)
disable-model-invocation: true
---

# Doctor orquesta

!`pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Doctor-Orquesta.ps1"`

Mostrale al usuario el diagnóstico de arriba tal cual y, si hay "Siguientes pasos", ofrecé ejecutar los que sean comandos (instalaciones, login) con su confirmación. Si todo está en ✓, decilo en una línea y sugerí `/orquesta:estado` para ver el enrutamiento o `/orquesta:arquitecto <objetivo>` para empezar.
