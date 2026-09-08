# Revisión — qué mira el arquitecto y qué delega

El arquitecto **no revisa código**: revisa el REPORTE y decide qué mandar al revisor. El revisor revisa código. Esta separación es lo que permite que el arquitecto corra en el modelo caro sin gastar tokens en diffs.

## Triage del REPORTE (2 minutos)
1. `Estado`:
   - `COMPLETADO` → al revisor (y al auditor si aplica).
   - `PARCIAL` → ¿lo que falta es de esta tarea? Si sí, reenviá al mismo agente con lo faltante (`SendMessage`), no lo mandes a revisión a medias. Si es de otra tarea, anotalo y mandá a revisar lo hecho.
   - `BLOQUEADO` → respondé la pregunta vos o pausá y preguntá al usuario. Nunca la ignores ni la "interpretes" hacia el trabajador.
2. Criterios: ¿todos los del BRIEF están listados? ¿los ✓ tienen evidencia (archivo:línea / salida)? Un ✓ sin evidencia se manda al revisor igual, pero anotalo: es señal de trabajador apurado.
3. `Propuestas` y decisiones tomadas por el trabajador: ratificalas o revertilas **ahora**, antes de que la siguiente tarea construya encima.
4. Archivos tocados fuera de "Modificar/Crear" → RECHAZADO directo sin pasar por el revisor; devolvé la tarea.

## Qué le pedís al revisor
Insumo: ruta del BRIEF, REPORTE (o ruta), intento, y si es reintento la ruta del dictamen anterior. Alcance opcional ("solo criterios 2 y 4", "todo"). Nada de "mirá si está bien": el revisor verifica criterios.

## Cuándo sumar al auditor de seguridad
Cualquier señal de `seguridad_si` en la tarea (SQL, capa de datos, entrada externa, auth, secretos, endpoints). Van en paralelo con el revisor sobre el mismo insumo. Los dos tienen que aprobar.

## Criterios específicos .NET dual-engine que el revisor conoce (para que el BRIEF los pida explícitamente cuando aplique)
- Parametrización total; nada de `$"... {valor}"` en SQL.
- Oracle: sin `OracleCommand` directo, `BindByName` cubierto por la capa central de acceso a datos del proyecto (p. ej. `IDbExecutor`).
- T-SQL vs PL/SQL: fechas, paginación (`TOP`/`OFFSET-FETCH` vs `FETCH FIRST`/`ROWNUM`), secuencias vs identity, `NVARCHAR`/`NVARCHAR2`, booleanos, concatenación con nulos.
- Stored procedures: precedencia `AND`/`OR`, índices que soportan los filtros, tablas temporales frente a subconsultas repetidas.
- Azure Functions: idempotencia en timers y colas, TTL e invalidación de cachés locales, configuración vía Key Vault + Managed Identity.
- Errores: sin `catch` vacíos, sin detalles internos al cliente, logs sin secretos.

## Después del dictamen
- `APROBADO` → `- [x]` en el PLAN + fila en `## Bitácora de revisión` (trabajador, modelo, intento, revisor, resultado).
- `RECHAZADO` → copiá al BRIEF los [Crítico]/[Debe] como sección `## Hallazgos a resolver (intento N+1)`, subí `intento:` en el frontmatter y reenviá al mismo agente. Al llegar a `max_reintentos_por_tarea`, escalá según `enrutamiento.md`.
- Hallazgos [Sugerencia] → decidís vos: se hacen en esta tarea, van a una tarea nueva, o a `## Diferido`.
