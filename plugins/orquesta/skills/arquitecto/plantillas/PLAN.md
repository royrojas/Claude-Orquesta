---
objetivo: {{OBJETIVO}}
estado: planificando
creado: {{FECHA}}
arquitecto: {{ARQUITECTO}}
rama: {{RAMA}}
---
# PLAN — {{OBJETIVO}}

> Estados válidos: `planificando` → `en-ejecucion` → `cerrado`. `pausado` = esperando al usuario o cambio trivial autorizado.
> Las compuertas leen `estado:` y los ítems `- [ ]` de **## Tareas**. Solo el revisor cierra `V.`.

## Clarificado
<!-- Una ronda de preguntas al inicio. Solo lo que cambiaría el código y el repo no responde. Formato: Q -> A -->
- Q1: … -> …
- Rama: {{RAMA}} (¿se trabaja aquí o en una rama nueva?) -> …

## Contexto (del cartógrafo)
<!-- Archivos clave, contratos existentes, convenciones, decisiones previas en Obsidian, riesgos. Máx 15 líneas. -->
- …

## Decisiones
<!-- ADR-lite: qué se decidió, por qué, qué se descartó. Se copian al ADR al cerrar. -->
- D1: … — por qué: … — descartado: …

## Enrutamiento
{{TABLA_ENRUTAMIENTO}}

Overrides de esta sesión (si el usuario pidió otro modelo): ninguno.

## Tareas
<!-- Una línea por tarea. Marcas: [ ] abierta · [x] aprobada por el revisor · [~] diferida con aprobación del usuario.
     Cada tarea: tier, brief, dependencias. "V." la marca únicamente el revisor tras la verificación final. -->
- [ ] 1. … — tier: implementador — brief: briefs/BRIEF-01.md — depende: —
- [ ] 2. … — tier: implementador-senior — brief: briefs/BRIEF-02.md — depende: 1
- [ ] V. Verificación final (build + tests + criterios de todos los briefs) — revisor

## Bitácora de revisión
| # | Trabajador (modelo) | Intento | Revisor | Resultado | Notas |
|---|---|---|---|---|---|

## Diferido / fuera de alcance
- …
