---
brief: BRIEF-NN
tarea: "NN. <título tal como aparece en PLAN.md>"
tier: implementador | implementador-senior
modelo: <modelo efectivo según config>
intento: 1
plan: ../PLAN.md
---
# BRIEF-NN — <título>

> El trabajador NO ve la conversación ni el PLAN completo: todo lo que necesita está aquí. No puede preguntarle al usuario.
> Si algo ambiguo cambiaría el código, responde `BLOQUEADO` con la pregunta concreta y no adivina.

## Contexto mínimo
<!-- 3-6 líneas: qué sistema, qué parte, por qué esta tarea existe. Convenciones que aplican (CLAUDE.md, capa de acceso a datos, naming, etc.). -->

## Objetivo de la tarea
<!-- Una frase verificable. -->

## Archivos
- Leer primero: `ruta/A.cs`, `ruta/B.cs`
- Modificar: `ruta/C.cs`
- Crear: `ruta/D.cs`
- NO tocar: `ruta/E.cs` (razón)

## Contrato exacto
<!-- Firmas, DTOs, SQL, nombres de tabla/columna, mensajes de error, nombres de config. Copiable, no descrito. -->
```csharp
```

## Criterios de aceptación (verificables)
<!-- Numerados. Cada uno debe poder comprobarse con un comando, un test o una lectura de archivo:línea. -->
1. …
2. …
3. `dotnet build` sin warnings nuevos y `dotnet test --filter "<filtro>"` en verde.

## Restricciones
- No cambiar firmas públicas fuera de las listadas.
- No agregar paquetes NuGet sin indicarlo en el reporte como `PROPUESTA`.
- Datos: siempre parámetros (nunca concatenar SQL); Oracle y SQL Server si la capa es dual.
- Secretos: nunca en código ni en config plano; Key Vault / Managed Identity.

## Cómo verificar
```powershell
dotnet build <ruta.sln> -warnaserror
dotnet test <ruta.csproj> --filter "<filtro>"
```

## Formato del reporte
Respondé con la plantilla REPORTE (máx 40 líneas). Si el detalle es más largo, guardalo en `.orquesta/reportes/REPORTE-NN.md` y citá la ruta.
