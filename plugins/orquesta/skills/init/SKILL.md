---
name: init
description: Crea la configuración de orquesta para este proyecto (.claude/orquesta.json) y te pregunta qué modelo y motor usa cada trabajador - quién implementa, quién toma las tareas difíciles, quién revisa - dónde van las notas de cierre (repo, vault de Obsidian, o ninguna) y el razonamiento de Codex si lo elegís, escribiendo solo lo que elegiste sobre un esqueleto mínimo y editable. Funciona sin Obsidian, sin graphify y sin ningún otro skill. Pre-llena las carpetas de Obsidian desde el CLAUDE.md del proyecto si tiene la sección "Memoria del proyecto (Obsidian)". No sobreescribe una config existente sin preguntar. Usalo la primera vez que uses orquesta en un proyecto, o cuando /orquesta:doctor diga que no hay config de proyecto.
argument-hint: [sin argumentos]
allowed-tools: Bash(pwsh *), PowerShell(pwsh *)
disable-model-invocation: true
---

# Init de orquesta

!`pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Initialize-OrquestaConfig.ps1"`

Arriba está el resultado del script: creó `.claude/orquesta.json` (un esqueleto con `_doc`, más las carpetas de Obsidian si las encontró en el CLAUDE.md) o avisó que ya existía. Decíselo al usuario en una línea. Si ya existía, preguntale primero si quiere que le agregues o cambies cosas ahí; sin esa confirmación no lo toques.

Todo lo que sigue funciona **sin Obsidian, sin graphify y sin `configurar-proyecto`**: son opcionales. Con los defaults, las notas de cierre quedan dentro del repo y el cartógrafo trabaja con Glob/Grep.

## Preguntá (una sola ronda)

Con `AskUserQuestion`, en **una** llamada, con opciones concretas y la recomendada marcada:

1. **¿Quién implementa?** (`implementador`) — Claude Sonnet (default) · Codex con el modelo default de su `~/.codex/config.toml` · Claude Opus · Codex con un modelo específico (lo escribe en "Other", por ejemplo `gpt-5.6-terra`).
2. **¿Quién toma las tareas difíciles?** (`implementador-senior`: migraciones, SQL dual-engine, concurrencia) — Claude Opus (default) · Codex con su modelo más capaz (por ejemplo `gpt-6-astra`) · igual que el implementador.
3. **¿Quién revisa y audita?** (`revisor` y `auditor-seguridad`, mismo valor) — Claude Opus (default, recomendado) · Claude Fable (máxima exigencia; cuidá la cuota) · Codex · Claude Sonnet (barato, solo para tareas triviales).
4. **¿Dónde van las notas de cierre (ADR y HANDOFF)?** — **solo si el script no las pre-llenó desde el CLAUDE.md** — Dentro del repo, en `docs/decisiones` (default; no hace falta Obsidian) · En mi vault de Obsidian (escribe la ruta absoluta de la carpeta en "Other") · No quiero notas de cierre.

Si alguna respuesta fue Codex, una segunda pregunta corta: **razonamiento** de Codex — `high` (recomendado) · `medium` · `xhigh` · `low`. Es una sola perilla para todos los trabajadores que corran en Codex (el modelo sí es por rol).

## Escribí solo lo que eligió

- En `.claude/orquesta.json`, **solo las claves que eligió**, fusionadas sobre el esqueleto: no borres los `_doc`. Valores válidos: motor `claude` con modelo `haiku` | `sonnet` | `opus` | `fable`; motor `codex` con `modelo` = el slug que indicó, o sin `modelo` para usar el default de su Codex. El razonamiento va en `motores.codex.razonamiento`.
- Notas de cierre: "dentro del repo" → no escribas nada (es el default). "Vault" → `contexto.obsidian.carpeta_decisiones` y `carpeta_handoffs` con esa misma ruta. "No quiero" → `contexto.obsidian.usar: false`. Si el script ya las pre-llenó, no las toques.
- Si para un rol eligió el default del plugin, **no escribas esa clave**: así sigue al día cuando el plugin cambie el default.
- Si quien implementa y quien revisa quedaron en el mismo modelo del mismo proveedor, avisale en una línea que pierde la mirada independiente (la regla del protocolo es que sean modelos o proveedores distintos) — y respetá su elección igual.

Cerrá corriendo `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Show-Estado.ps1"` y mostrale la tabla de enrutamiento efectiva tal cual: es la confirmación de qué quedó y de qué archivo sale cada valor.
