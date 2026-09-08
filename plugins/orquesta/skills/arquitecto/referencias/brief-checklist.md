# BRIEF — checklist antes de delegar

Un BRIEF es bueno cuando un trabajador que **no vio nada** de la conversación puede terminarlo sin preguntar y el revisor puede aprobarlo sin interpretar. Antes de llamar al Agent tool, recorré esto:

## Contexto mínimo (3-6 líneas)
- [ ] Qué sistema y qué parte (proyecto de la solución, capa).
- [ ] Por qué existe la tarea (una frase; evita "optimizaciones" bienintencionadas fuera de alcance).
- [ ] Convenciones que aplican y dónde leerlas (`CLAUDE.md`, capa de datos, naming).

## Contrato exacto (copiable, no descrito)
- [ ] Firmas completas con tipos y namespaces. "Un método que devuelve los cierres" es una descripción; `Task<IReadOnlyList<CierreCajaDto>> ObtenerCierresAsync(DateOnly desde, DateOnly hasta, CancellationToken ct)` es un contrato.
- [ ] DTOs con sus propiedades. Tablas/columnas con nombres reales (los que dio el cartógrafo, no los que "deberían" ser).
- [ ] SQL: para dual-engine, o das ambas variantes o das el contrato de la capa (`IDbExecutor`) y decís explícitamente "sin SQL directo".
- [ ] Mensajes de error y códigos de retorno si el usuario los ve.
- [ ] Nombres de configuración (`appsettings`, Key Vault) exactos.

## Criterios de aceptación (numerados, verificables)
- [ ] Cada criterio se puede comprobar con: un test con nombre, un comando con salida esperada, o una lectura `archivo:línea`.
- [ ] Incluye el caso negativo relevante (entrada inválida, sin datos, error de BD).
- [ ] Incluye `dotnet build` (idealmente `-warnaserror` si el proyecto lo soporta) y el filtro de tests.
- [ ] Ningún criterio dice "funciona correctamente", "es limpio", "sigue buenas prácticas".

## Archivos
- [ ] Leer primero / Modificar / Crear / **NO tocar** (con motivo). El "NO tocar" evita el 80 % de los conflictos entre tareas paralelas.

## Restricciones
- [ ] Alcance cerrado: qué NO hacer aunque parezca obvio.
- [ ] Prohibido: nuevos paquetes sin `PROPUESTA`, cambios de firma pública no listados, secretos en código, SQL concatenado, `git commit`.

## Verificación y reporte
- [ ] Comandos exactos (ruta del `.sln`/`.csproj`, filtro).
- [ ] Recordatorio del formato REPORTE y del límite de 40 líneas.

## Errores típicos que producen rechazos
1. **Contrato ambiguo** → el trabajador elige nombres distintos a los que esperaba la tarea siguiente.
2. **Criterio no verificable** → el revisor no puede aprobar y la tarea rebota sin culpa del trabajador.
3. **Dependencia oculta** → la tarea necesita algo que otra tarea aún no entregó; en el PLAN ponela como `depende:`.
4. **Alcance abierto** → el trabajador "aprovecha" y toca archivos de otra tarea paralela.
5. **Tests inexistentes** → pedís `dotnet test` en un proyecto sin proyecto de tests; decidí antes si la tarea incluye crearlo.
6. **Brief gigante** → si el BRIEF pasa de ~120 líneas, son dos tareas.
