---
name: revisar
description: Revisión independiente con ojos frescos de una entrega del protocolo orquesta - corre en un subagente revisor (solo lectura + build/tests) que verifica los criterios de aceptación de un BRIEF contra el código real y dictamina APROBADO o RECHAZADO con evidencia. Usalo cuando el usuario pida "revisá la tarea N", "verificá el brief", "hacé la verificación final" o quiera un segundo par de ojos sobre un cambio, aun fuera de una orquestación (pasale la ruta o el alcance).
argument-hint: [BRIEF-NN | ruta | "final" | alcance libre]
context: fork
agent: orquesta:revisor
background: false
disable-model-invocation: true
---

Verificá lo siguiente con el protocolo del revisor de orquesta: $ARGUMENTS

Reglas de resolución del alcance:
- Si el argumento es `BRIEF-NN`, el brief está en `.orquesta/briefs/BRIEF-NN.md` y el reporte, si existe, en `.orquesta/reportes/REPORTE-NN.md`.
- Si el argumento es `final` o `V.`, hacé la verificación final del PLAN (`.orquesta/PLAN.md`): build + tests completos + criterios de todos los briefs marcados `[x]`.
- Si es una ruta o una descripción libre y no hay BRIEF, derivá los criterios del `git diff` y de lo que el usuario pidió, y decilo explícitamente en el dictamen ("criterios inferidos").
- Si no se pasó argumento, revisá el `git diff` actual contra la rama base.

Devolvé el dictamen con el formato del revisor (máx 40 líneas). No corrijas código.
