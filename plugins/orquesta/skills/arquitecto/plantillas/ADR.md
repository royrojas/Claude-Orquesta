---
tipo: adr
titulo: "{{TITULO}}"
proyecto: "{{PROYECTO}}"
fecha: {{FECHA}}
estado: aceptada
arquitecto: {{ARQUITECTO}}
tags: [adr, orquesta, {{TAGS}}]
relacionados: []
---
# ADR — {{TITULO}}

## Contexto
<!-- Qué problema había, qué restricciones aplicaban (dual-engine, Azure Functions, Key Vault, etc.). -->

## Decisión
<!-- Qué se decidió, en una o dos frases. Luego los detalles del contrato si son relevantes. -->

## Alternativas consideradas
- **A** — descartada porque …
- **B** — descartada porque …

## Consecuencias
- Positivas: …
- Costos / deuda asumida: …
- Qué habría que revisar si cambia X: …

## Trazabilidad
- Plan: [[PLAN — {{TITULO}}]] (`.orquesta/PLAN.md`, commit `{{COMMIT}}`)
- Briefs: BRIEF-01 … BRIEF-NN
- Verificación: aprobada por orquesta:revisor el {{FECHA}}
- Handoff: [[{{HANDOFF}}]]
