# Enrutamiento — qué modelo hace qué

La regla de fondo: **el modelo caro piensa y juzga; el modelo barato ejecuta lo que ya está decidido.** El costo de una orquestación se va en tres lugares: el arquitecto leyendo el repo (evitar: cartógrafo), los trabajadores re-descubriendo contexto (evitar: BRIEF completo) y los reintentos (evitar: criterios verificables).

## Tabla de decisión por tarea

| Situación | Tier | Por qué |
|---|---|---|
| CRUD, mapeos, DTOs, endpoints con contrato dado, tests unitarios, refactor local, PowerShell de tooling | `implementador` | El contrato ya está en el BRIEF; el modelo solo tiene que seguirlo con cuidado. |
| Migraciones, SQL Server + Oracle a la vez, stored procedures, transacciones/concurrencia, Azure Functions con triggers, Key Vault/Managed Identity, cambios que cruzan 3+ proyectos de la solución | `implementador-senior` | Equivocarse cuesta caro y la corrección requiere juicio, no solo obediencia. |
| Tarea devuelta `BLOQUEADO` dos veces o `RECHAZADO` `max_reintentos_por_tarea` veces | escalar un tier | Reintentar en el mismo tier con el mismo BRIEF rara vez cambia el resultado. |
| Cualquier tarea que toque SQL, capa de datos, entrada externa, auth, secretos | + `auditor-seguridad` en la revisión | Un revisor generalista no busca inyección con la misma insistencia. |
| Recon, "¿dónde está X?", "¿cómo se prueba esto?" | `cartografo` | Solo lectura, modelo barato, resultado acotado. |
| ADR, HANDOFF, refrescar grafo | `documentador` | Plantilla + hechos del PLAN; no requiere juicio de arquitectura. |

Las señales `senior_si` y `seguridad_si` de la config son subcadenas a buscar en título + descripción de la tarea (sin distinguir mayúsculas). Se pueden ajustar por proyecto en `.claude/orquesta.json`.

## Escalado (de ida, nunca de vuelta)
`implementador → implementador-senior → arquitecto redacta un BRIEF más fino (tarea partida en 2-3) → vuelve a implementador-senior`.
El arquitecto **no implementa** al escalar: si el senior no pudo, el problema casi siempre es el BRIEF (contrato incompleto, criterio no verificable, dependencia oculta), no el modelo.

Nunca reformules una tarea rechazada para que "pase": si un criterio no se puede cumplir, se difiere `[~]` con aprobación del usuario y queda escrito en `## Diferido`.

## Paralelismo
- Paralelizá solo tareas sin dependencia de archivos ni de contrato entre sí. Dos trabajadores editando el mismo archivo = conflicto garantizado.
- Máximo `limites.max_paralelo` (por defecto 3). Más no acelera: te satura a vos con reportes.
- Si dos tareas comparten un contrato nuevo (una interfaz, una tabla), la que lo **define** va primero y sola; las que lo consumen van después, en paralelo.
- Un trabajador en `isolation: worktree` solo si el usuario lo pidió: la mayoría de las tareas .NET necesitan el mismo checkout para compilar la solución completa.

## Overrides del usuario
Si el usuario dice "usá opus para todo", "no gastes Fable" o similar, eso manda sobre la config **para esta orquestación**. Anotalo en `## Enrutamiento → Overrides` del PLAN y usá esos modelos en cada llamada. Para hacerlo permanente, indicale que lo ponga en `.claude/orquesta.json` (proyecto) o `~/.claude/orquesta.json` (usuario) y `/orquesta:estado` para comprobarlo.

## Motor Codex (Fable planea, Codex ejecuta)
Cualquier trabajador puede correr en OpenAI Codex CLI en vez de un subagente de Claude: `trabajadores.<nombre>.motor: "codex"` y, opcionalmente, `modelo` con un modelo de Codex (vacío = el default de `~/.codex/config.toml`). El arquitecto lo invoca con `scripts/Invoke-Codex.ps1`, que inyecta las mismas instrucciones del rol (`agents/<rol>.md`), aplica las compuertas de PLAN/BRIEF, guarda el REPORTE y registra tokens en la bitácora. Combinaciones útiles: (a) Codex implementa y Claude revisa — revisión entre proveedores distintos; (b) Claude implementa y `revisor.motor: codex` — segundo par de ojos de otro modelo; (c) todo Codex salvo el arquitecto, cuando querés cuidar la cuota de Claude. Lo que no cambia: el arquitecto es siempre la sesión de Claude Code, el BRIEF es el contrato, y quien implementó no se revisa a sí mismo.

## Cuándo NO orquestar
Un cambio de una función, un typo, un ajuste de config: hacelo directo (o que lo haga el usuario) y no abras PLAN. El protocolo paga cuando hay 3+ tareas, riesgo real o necesidad de dejar trazabilidad (ADR/HANDOFF). Si dudás, preguntale al usuario en una línea.
