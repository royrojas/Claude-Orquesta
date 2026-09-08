# Changelog

## 1.3.0 — 2026-09-08
- Motor Codex: prompt en bloques XML según la guía de prompting de OpenAI para GPT-5.x (task, follow-through, action_safety, verification_loop, grounding, contrato de salida).
- Salida estructurada de Codex con `--output-schema` (`schemas/reporte.schema.json`, `schemas/revision.schema.json`): estado/dictamen, criterios con evidencia, hallazgos con severidad y confianza; JSON guardado y renderizado al formato REPORTE/REVISIÓN. `motores.codex.salida_estructurada` para apagarlo.
- `/orquesta:doctor` (`Doctor-Orquesta.ps1`): diagnóstico de pwsh, hooks, config, Codex CLI y login, plugin oficial de OpenAI, graphify, Obsidian, git.
- Cierre del PLAN: paso opcional `/codex:adversarial-review` si el plugin de OpenAI está instalado.
- 166 aserciones.

## 1.2.0 — 2026-09-08
- Compuerta de delegación valida la forma del BRIEF referenciado (criterios numerados, comandos de verificación, `NO tocar`, sin marcadores); `scripts/Test-Brief.ps1` para comprobarlo antes de delegar. El wrapper de Codex aplica la misma regla.
- Hook `SessionStart` (`Aviso-Sesion.ps1`): recuerda el PLAN abierto y sus tareas al abrir, reanudar o compactar la sesión.
- CI en GitHub Actions: suite completa en windows-latest y ubuntu-latest; `.gitattributes` con LF.
- 150 aserciones.

## 1.1.0 — 2026-09-08
- Motor `codex`: cualquier trabajador puede correr en OpenAI Codex CLI (`codex exec`) con las mismas instrucciones de rol, compuertas, REPORTE y bitácora; reintentos con `resume`.
- `Show-Estado` e `Initialize-Orquesta` muestran el motor por trabajador y la disponibilidad de `codex`.
- 18 aserciones nuevas con un `codex` falso.

## 1.0.0 — 2026-09-08
- Protocolo arquitecto en 5 fases (`/orquesta:arquitecto`), revisión bajo demanda (`/orquesta:revisar`), estado (`/orquesta:estado`).
- Seis subagentes con modelo configurable por tier: cartografo, implementador, implementador-senior, revisor, auditor-seguridad, documentador.
- Cuatro compuertas en PowerShell 7: delegación, arquitecto-no-edita, cierre, bitácora.
- Config con merge defaults ← usuario ← proyecto; plantillas PLAN/BRIEF/REPORTE/ADR/HANDOFF; integración graphify + Obsidian.
- Suite de pruebas sin dependencias (117 aserciones).
