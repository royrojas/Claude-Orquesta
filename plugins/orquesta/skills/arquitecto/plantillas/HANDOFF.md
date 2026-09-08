---
tipo: handoff
titulo: "{{TITULO}}"
proyecto: "{{PROYECTO}}"
fecha: {{FECHA}}
rama: {{RAMA}}
estado: cerrado | parcial
tags: [handoff, orquesta]
---
# HANDOFF — {{TITULO}}

## Qué se entregó
- … (archivos/componentes, en 3-8 líneas)

## Cómo se verificó
- `dotnet build …` / `dotnet test …` → resultado
- Revisor: APROBADO en intento N (ver `.orquesta/PLAN.md` → Bitácora de revisión)
- Auditoría de seguridad: APROBADO | no aplicaba

## Decisiones clave
- [[ADR — {{TITULO}}]]

## Lo que quedó fuera / diferido
- … (con el motivo y quién lo aprobó)

## Para continuar
1. Leer `.orquesta/PLAN.md` y este handoff.
2. Si el grafo está viejo: `graphify update .`
3. Siguiente paso sugerido: …

## Costos de la orquestación
<!-- Del Show-Estado: delegaciones por modelo. Sirve para calibrar el enrutamiento. -->
- …
