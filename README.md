# claude-orquesta

![pruebas](https://github.com/royrojas/Claude-Orquesta/actions/workflows/tests.yml/badge.svg)

**Claude Code como arquitecto.** Fable/Opus planea, escribe los briefs y revisa; subagentes de Claude o Codex implementan con el modelo que vos elegís. Cinco compuertas en PowerShell 7 hacen cumplir el protocolo. Integra graphify y Obsidian.

```
/plugin marketplace add royrojas/Claude-Orquesta
/plugin install orquesta@orquesta
/reload-plugins
/orquesta:init          ← en cada proyecto, la primera vez: crea la config y te pregunta los modelos
/orquesta:doctor        ← siempre después de init: valida lo que quedó
/orquesta:arquitecto Exportar los cierres de caja a CSV desde el POS
```

¿Qué modelo hace qué? Se decide en un JSON de tres líneas: ver [§6, ejemplos A–F](#ejemplos-de-configuración-listos-para-copiar).

---

## Ejemplo rápido

Con el plugin instalado (arriba) y, si vas a usar Codex, `codex login` ya hecho. No hace falta Obsidian ni graphify: son opcionales, y sin ellos las notas de cierre quedan dentro del repo.

1. Arrancás la sesión con el modelo caro como arquitecto — nunca lo cambia el plugin por vos — y, la primera vez en un proyecto, creás la config y validás, **siempre en este orden**:
   ```
   claude --model fable
   /orquesta:init        ← crea .claude/orquesta.json y te pregunta los modelos (si ya existe, no lo toca)
   /orquesta:doctor      ← valida el entorno con esa config
   ```
2. Le pedís algo:
   ```
   /orquesta:arquitecto Exportar los cierres de caja a CSV desde el POS
   ```
3. El arquitecto manda a `cartografo` a mapear el repo, te hace **una sola ronda** de preguntas, y te presenta un PLAN con las tareas y qué trabajador va a cada una. Vos lo aprobás.
4. Delega cada tarea al trabajador que corresponda —subagente de Claude o proceso de Codex CLI, según cómo lo configuraste— y cada entrega pasa por un `revisor` independiente antes de marcarse hecha.
5. Al cerrar: `documentador` deja ADR + HANDOFF en tu Obsidian, y vos hacés el commit (el plugin nunca commitea).

**¿Cómo le decís qué modelo hace cada tarea?** Con un JSON en `.claude/orquesta.json` del proyecto — `/orquesta:init` te lo crea vacío y editable (o `~/.claude/orquesta.json` si querés algo para todos los tuyos). Ejemplo real, mezclando Claude y Codex — el que revisa nunca es el mismo proveedor que el que implementó:

```json
{
  "trabajadores": {
    "implementador":        { "motor": "codex",  "modelo": "gpt-5.6-terra" },
    "implementador-senior": { "motor": "codex",  "modelo": "gpt-6-astra" },
    "revisor":              { "motor": "claude", "modelo": "opus" },
    "auditor-seguridad":    { "motor": "claude", "modelo": "opus" }
  },
  "motores": { "codex": { "razonamiento": "high" } }
}
```

(`gpt-5.6-terra` y `gpt-6-astra` son modelos de Codex, no de Claude — la lista vigente puede cambiar, ver [§8](#qué-modelos-de-codex-podés-poner-en-modelo). No hace falta declarar los seis trabajadores: solo las claves que cambiás respecto al default.)

Si preferís decírselo por el chat en vez de un archivo ("usá opus para el revisor en esto"), también funciona — ver [§6](#cambiar-modelos-desde-el-chat). Los seis trabajadores posibles, con sus modelos y herramientas, están en [§7](#7-los-trabajadores). El resto de este manual desglosa cada pieza; seguí por el [tutorial completo](#4-tutorial-tu-primera-orquestación-de-principio-a-fin) o andá directo al índice de abajo.

---

## Índice

- [Ejemplo rápido](#ejemplo-rápido)

1. [Qué es y qué problema resuelve](#1-qué-es-y-qué-problema-resuelve)
2. [Conceptos en dos minutos](#2-conceptos-en-dos-minutos)
3. [Requisitos e instalación](#3-requisitos-e-instalación)
4. [Tutorial: tu primera orquestación de principio a fin](#4-tutorial-tu-primera-orquestación-de-principio-a-fin)
5. [Comandos](#5-comandos)
6. [Configuración: qué modelo hace qué](#6-configuración-qué-modelo-hace-qué)
7. [Los trabajadores](#7-los-trabajadores)
8. [Codex como motor](#8-codex-como-motor)
9. [El PLAN](#9-el-plan)
10. [El BRIEF](#10-el-brief)
11. [REPORTE y REVISIÓN](#11-reporte-y-revisión)
12. [Las compuertas](#12-las-compuertas)
13. [graphify, Obsidian y la documentación que deja](#13-graphify-obsidian-y-la-documentación-que-deja)
14. [Bitácora y métricas](#14-bitácora-y-métricas)
15. [Recetas para situaciones comunes](#15-recetas-para-situaciones-comunes)
16. [Solución de problemas](#16-solución-de-problemas)
17. [Convivencia con el plugin oficial de OpenAI](#17-convivencia-con-el-plugin-oficial-de-openai)
18. [Estructura del repo, pruebas y contribuir](#18-estructura-del-repo-pruebas-y-contribuir)

---

## 1. Qué es y qué problema resuelve

Cuando le pedís a Claude Code una feature de varios pasos, el mismo modelo hace todo: entiende, decide, escribe, prueba y se revisa a sí mismo. Eso tiene tres problemas:

- **Cuesta caro.** Un modelo de primera línea leyendo el repo, escribiendo boilerplate y corriendo tests gasta tokens de primera línea en trabajo de segunda.
- **Nadie revisa.** El que escribe el código es el que dice que está bien. Los errores de contrato (nombres distintos, una firma que la siguiente tarea no esperaba) aparecen tarde.
- **No queda rastro.** Terminó la sesión y las decisiones se fueron con ella.

**orquesta** separa los roles como en un equipo real:

| Rol | Quién | Qué hace |
|---|---|---|
| **Arquitecto** | La sesión de Claude Code (Fable u Opus) | Habla con vos, clarifica, diseña, escribe el PLAN y un BRIEF por tarea, aprueba. **No escribe código.** |
| **Trabajadores** | Subagentes de Claude (Haiku/Sonnet/Opus) o procesos de Codex | Cada uno ejecuta exactamente un BRIEF y devuelve un REPORTE corto con evidencia. |
| **Revisor** | Subagente independiente con contexto limpio | Verifica criterio por criterio contra el código real; es el único que cierra tareas. |
| **Documentador** | Subagente | Deja ADR y HANDOFF en tu carpeta de Obsidian y refresca el grafo de graphify. |

Y para que el protocolo no dependa de que el modelo "se acuerde", cinco **compuertas** (hooks de Claude Code escritos en PowerShell 7) lo hacen cumplir: sin PLAN aprobado no se delega, sin BRIEF válido no se implementa, el arquitecto no toca código mientras hay un PLAN en ejecución, y no se cierra el turno con tareas abiertas sin decir qué pasa con ellas.

Todo corre **desde la terminal de Claude Code**. Codex, si lo usás, corre como proceso en segundo plano; nunca abrís su interfaz.

## 2. Conceptos en dos minutos

```
 vos ──► /orquesta:arquitecto "objetivo"
              │
              ├─ 1. cartógrafo (sonnet)  lee graphify + Obsidian + repo → mapa
              ├─ 2. clarificar           una sola ronda de preguntas, todas juntas
              ├─ 3. PLAN.md              decisiones + tareas con tier → vos aprobás
              ├─ 4. BRIEF-NN.md ──► implementador (sonnet) / senior (opus) / codex
              │                                  │ REPORTE (≤40 líneas)
              ├─ 5. revisor (opus) ◄─────────────┘  APROBADO → [x]   RECHAZADO → reintento/escalado
              │     + auditor-seguridad si toca SQL/datos/auth/secretos
              └─ 6. verificación final → documentador (ADR + HANDOFF, graphify update) → cerrado
```

- **PLAN** (`.orquesta/PLAN.md`): el libro mayor. Lo clarificado, las decisiones, la tabla de enrutamiento y una línea por tarea con su marca: `[ ]` abierta, `[x]` aprobada por el revisor, `[~]` diferida con tu aprobación. Tiene un `estado:` que las compuertas leen: `planificando` → `en-ejecucion` → `cerrado`, más `pausado` como válvula de escape.
- **BRIEF** (`.orquesta/briefs/BRIEF-NN.md`): la especificación autocontenida de una tarea. El trabajador no ve la conversación ni el PLAN; todo lo que necesita está en el BRIEF: contexto mínimo, archivos a tocar y a **no** tocar, contrato exacto (firmas, DTOs, SQL), criterios de aceptación numerados y verificables, comandos para verificar.
- **Tier**: qué tan capaz tiene que ser quien implementa. `implementador` (Sonnet) para lo estándar, `implementador-senior` (Opus) para migraciones, SQL dual-engine, concurrencia, Azure Functions, Key Vault. La config decide con señales por palabra clave.
- **Motor**: en qué corre un trabajador. `claude` (subagente de Claude Code) o `codex` (proceso `codex exec` de OpenAI Codex CLI). Se configura por trabajador.
- **REPORTE**: lo que devuelve un trabajador. Máximo 40 líneas: estado (`COMPLETADO` / `PARCIAL` / `BLOQUEADO`), cambios, cada criterio ✓/✗ con evidencia, pruebas ejecutadas, dudas, propuestas no aplicadas. Un ✓ sin evidencia cuenta como ✗.
- **REVISIÓN**: el dictamen del revisor. `APROBADO` o `RECHAZADO`, criterio por criterio, con hallazgos `[Crítico]`, `[Debe]`, `[Sugerencia]`.
- **Compuertas**: hooks que bloquean lo que rompe el protocolo y te avisan por qué.

## 3. Requisitos e instalación

### Requisitos

| Requisito | Para qué | Cómo se consigue |
|---|---|---|
| Claude Code reciente | Plugins, subagentes con `model`, skills con `context: fork`, hooks | `npm i -g @anthropic-ai/claude-code` |
| **PowerShell 7** (`pwsh`) en el PATH | Todas las compuertas y scripts | Windows: `winget install Microsoft.PowerShell` · macOS: `brew install powershell` · Linux: paquete `powershell` |
| Codex CLI *(opcional)* | Solo si algún trabajador usa `motor: codex` | `npm i -g @openai/codex` y `codex login` |
| graphify *(opcional)* | Mapa del repo más barato y mejor para el cartógrafo | Ver [graphify](https://github.com/safishamsi/graphify); genera `graphify-out/` |
| Carpeta de decisiones *(opcional)* | ADR y HANDOFF en tu vault de Obsidian | Por defecto `docs/decisiones`/`docs/handoffs`, dentro del repo. Para un vault externo (fuera del repo, en otra ruta por persona): `contexto.obsidian.vault_root` en tu `~/.claude/orquesta.json` **personal** — ver [§13](#13-graphify-obsidian-y-la-documentación-que-deja). |

Windows con PowerShell 5.1 solo **no alcanza**: los scripts usan sintaxis de PowerShell 7 y `pwsh` tiene que estar en el PATH que ve Claude Code.

### Instalar como plugin (recomendado)

Dentro de Claude Code:

```
/plugin marketplace add royrojas/Claude-Orquesta
/plugin install orquesta@orquesta
/reload-plugins
/orquesta:doctor
```

`/orquesta:doctor` te dice si `pwsh` está, si los hooks cargaron, qué motores tenés configurados y qué falta. Corré siempre esto después de instalar. Y en cada proyecto, el orden es fijo: **`/orquesta:init` → `/orquesta:doctor`** — init crea la config (es idempotente: si ya existe no la toca), doctor valida lo que quedó. Al revés te confunde: doctor te reporta una config que init está a punto de cambiar.

### Instalar desde una carpeta local (para desarrollar el plugin)

```
git clone https://github.com/royrojas/Claude-Orquesta.git
/plugin marketplace add C:\ruta\Claude-Orquesta
/plugin install orquesta@orquesta
```

> **No copies las skills a `~/.claude/skills/` a mano.** Funcionan, pero perdés las compuertas (los hooks de plugin no se copian) y `${CLAUDE_PLUGIN_ROOT}` no se sustituye. Instalalo como plugin.

### Verificar

```
/orquesta:init        → config del proyecto (te pregunta los modelos; si ya existe, no la toca)
/orquesta:doctor      → todo en ✓ (o te dice qué falta y cómo) — siempre después de init
/orquesta:estado      → tabla de trabajadores con motor y modelo
```

## 4. Tutorial: tu primera orquestación de principio a fin

Supongamos un proyecto .NET con SQL Server y Oracle. Queremos exportar los cierres de caja a CSV.

### Paso 0 — Arrancá con el modelo caro como arquitecto

```
claude --model fable
```

(o `/model fable` dentro de la sesión). El plugin no puede cambiar el modelo de la sesión por vos; si arrancás en otro, el arquitecto te lo avisa una vez y sigue.

### Paso 1 — Pedí el objetivo

```
/orquesta:arquitecto Exportar los cierres de caja a CSV desde el POS, con filtro por rango de fechas
```

Lo primero que ves es el **estado del proyecto** (inyectado por el plugin): tabla de enrutamiento efectiva, si hay PLAN, si hay grafo de graphify, rama de git.

### Paso 2 — El cartógrafo mapea (Sonnet, solo lectura)

El arquitecto delega a `orquesta:cartografo`, que lee `graphify-out/GRAPH_REPORT.md` si existe, busca decisiones previas en `docs/decisiones`, y localiza archivos, contratos, convenciones y cómo se corren los tests. Devuelve un mapa de ≤ 60 líneas. El arquitecto **no lee el repo** por su cuenta: lee el mapa.

### Paso 3 — Una sola ronda de preguntas

El arquitecto te pregunta todo lo que cambiaría el código y el repo no responde, de una vez:

> 1. ¿El CSV lo descarga el usuario desde la pantalla de cierres o lo genera un job?
> 2. Formato de fechas y separador: ¿`;` por Excel en español?
> 3. ¿Rango máximo permitido? ¿Qué pasa si no hay cierres en el rango?
> 4. ¿Se trabaja en la rama actual (`feature/reportes`) o en una nueva?

Contestás una vez. Los trabajadores no pueden preguntarte nada: por eso esta fase existe. Si decís "decidí vos", la decisión queda anotada como del arquitecto.

### Paso 4 — El PLAN

El arquitecto crea `.orquesta/PLAN.md` (con `Initialize-Orquesta.ps1`, que ya deja la tabla de enrutamiento de tu config) y lo completa. Te presenta un resumen:

> **Decisiones:** D1 endpoint `GET /api/cierres/export?desde&hasta` en `Cierres.Api`; D2 generación en streaming con `CsvHelper` (ya está en la solución); D3 rango máximo 92 días, 400 si se excede.
> **Tareas:** 1. servicio `ICierreExportService` (implementador) · 2. endpoint + validación (implementador, depende de 1) · 3. consulta dual-engine SQL Server/Oracle (implementador-senior + auditor) · 4. tests de integración (implementador, depende de 2 y 3).
> **Fuera de alcance:** programación de envíos por correo.
> ¿Aprobás el plan?

Con tu OK, el PLAN pasa a `estado: en-ejecucion`. **Sin ese OK, la compuerta de delegación bloquea cualquier intento de implementar.**

### Paso 5 — BRIEF y delegación

Por cada tarea lista, el arquitecto escribe `.orquesta/briefs/BRIEF-01.md` (ver [§10](#10-el-brief)), lo valida con `Test-Brief.ps1` y llama al trabajador con el modelo de tu tabla. Las tareas 1 y 3 no dependen entre sí, así que van en paralelo (máximo `limites.max_paralelo`).

Si un trabajador devuelve `BLOQUEADO` ("¿la columna es `FechaCierre` o `FECHA_CIERRE` en Oracle?"), el arquitecto decide, actualiza el BRIEF y le responde **al mismo agente** para que conserve su contexto.

### Paso 6 — Revisión

Cada REPORTE va a `orquesta:revisor` (Opus, contexto limpio): lee el BRIEF, mira el `git diff`, corre `dotnet build` y `dotnet test` **él mismo**, y dictamina. La tarea 3 (SQL) va además a `orquesta:auditor-seguridad`.

- `APROBADO` → el arquitecto marca `[x]` en el PLAN.
- `RECHAZADO` → los hallazgos `[Crítico]`/`[Debe]` se copian al BRIEF y vuelve al mismo trabajador. Al segundo rechazo, escala de tier: `implementador → implementador-senior → el arquitecto parte la tarea en briefs más finos`. Nunca hacia abajo, nunca "reformulando" la tarea para que pase.

### Paso 7 — Cierre

Con todas las tareas `[x]` (o `[~]` diferidas con tu aprobación explícita), el revisor hace la **verificación final** (`V.`: build + tests completos + criterios de todos los briefs). Luego `orquesta:documentador` escribe `docs/decisiones/ADR-20260908-export-csv-cierres.md` y `docs/handoffs/HANDOFF-20260908-export-csv-cierres.md`, y corre `graphify update .`. El PLAN pasa a `estado: cerrado` y recibís un resumen: qué se entregó, decisiones, diferidos, cómo se verificó y el costo medido por actor y modelo (la tabla de `/orquesta:costos`). Si querés una retrospectiva, la escribe el documentador, no el arquitecto.

El commit lo hacés vos (o tu skill de commit). El plugin nunca hace `git commit` ni `git push`.

### Si se cortó la sesión

Volvé a abrir Claude Code en el proyecto: el hook `SessionStart` te avisa "PLAN 'Exportar cierres…' en estado en-ejecucion (2 abiertas)". Corré `/orquesta:arquitecto` sin argumentos y **reanuda** desde el PLAN y los briefs, sin volver a clarificar.

## 5. Comandos

### `/orquesta:arquitecto <objetivo>`

Corre el protocolo completo. Sin argumento y con PLAN abierto, reanuda.

```
/orquesta:arquitecto Migrar el cálculo de comisiones de stored procedure a C# manteniendo paridad
/orquesta:arquitecto Agregar auditoría de cambios a la tabla de precios (SQL Server y Oracle)
/orquesta:arquitecto                      ← reanudar el PLAN en ejecución
```

Solo corre cuando lo invocás con `/orquesta:arquitecto`. Ningún skill de orquesta se activa por su cuenta (`disable-model-invocation: true` en todos): pedir "hacelo con subagentes" o "modo arquitecto" en el chat no abre un PLAN ni delega nada, así que el modelo de la sesión trabaja directo hasta que vos lo llamás. Para un cambio de una función no hace falta el arquitecto: hacelo directo.

### `/orquesta:revisar [alcance]`

Revisión con ojos frescos bajo demanda. Corre en un subagente revisor (solo lectura + build/tests), aun fuera de una orquestación.

```
/orquesta:revisar BRIEF-03            ← criterios del brief contra el código real
/orquesta:revisar final               ← verificación final del PLAN (build + tests + todos los briefs)
/orquesta:revisar src/Cierres/        ← criterios inferidos del diff y de lo que pidas
/orquesta:revisar                     ← el git diff actual contra la rama base
```

### `/orquesta:estado`

Enrutamiento efectivo (trabajador → motor → modelo y de qué archivo sale), estado del PLAN y tareas abiertas, disponibilidad de graphify/Obsidian/Codex, rama de git y delegaciones por modelo acumuladas.

### `/orquesta:costos`

Cuánto costó la orquestación, **medido**: lee el `usage` real de cada request en los transcripts de Claude Code (`~/.claude/projects/<proyecto>/<sesión>.jsonl` para el arquitecto y `<sesión>/subagents/*.jsonl` para cada subagente), asocia cada subagente a su rol vía la bitácora, suma los tokens de Codex y valora todo con `costos.tarifas` (defaults del plugin, editables por proyecto). Una fila por actor y modelo: requests, contexto máximo, entrada, caché escrita, caché leída, salida (thinking incluido) y USD nominal. Debajo, las señales que importan: requests y contexto del arquitecto, costo por request y **arranques en frío** (requests que re-escribieron ≥ 100k de caché, típicamente por reanudar una sesión larga tras más de una hora o por cambiar de modelo con `/model`).

```
/orquesta:costos                              ← las sesiones que aparecen en .orquesta/bitacora.jsonl
/orquesta:costos -Sesion 2c954fcd-…           ← una sesión concreta (el id es el nombre del transcript)
```

Con suscripción los dólares son referencia, pero los tokens cuentan contra la cuota igual. Ver [§14](#14-bitácora-y-métricas) para lo que enseñó la primera medición.

### `/orquesta:doctor`

Diagnóstico del entorno: versión de PowerShell y `pwsh` en PATH, hooks y scripts del plugin, config válida y motores de los trabajadores, Codex CLI (versión y login) si algún trabajador lo usa, plugin oficial de OpenAI, graphify, carpeta de Obsidian, git, PLAN. Con "Siguientes pasos" cuando algo falta. Si el proyecto no tiene `.claude/orquesta.json`, te sugiere `/orquesta:init` (no lo crea él: doctor es solo lectura). Si el `CLAUDE.md` del proyecto declara una carpeta de Obsidian absoluta distinta de la que resuelve la config, lo marca con ✗ y te manda a `/orquesta:init` — solo lo lee para diagnosticar, la config sigue mandando.

### `/orquesta:init`

Crea `.claude/orquesta.json` en el proyecto si no existe: un esqueleto mínimo y editable con un `_doc` por bloque (`trabajadores`, `motores.codex`, `contexto.obsidian`). **No vuelca los defaults** — vacío de overrides se comporta igual que los defaults y sigue al día cuando el plugin cambia. Si el `CLAUDE.md` del proyecto tiene la sección "Memoria del proyecto (Obsidian)" con una línea `- Decisiones: <ruta absoluta>`, la pre-llena en `carpeta_decisiones` y `carpeta_handoffs` (si la ruta está abreviada o no es absoluta, no inventa nada). Nunca sobreescribe uno existente sin preguntar.

Después te pregunta, en una sola ronda, **quién implementa, quién toma las tareas difíciles y quién revisa/audita** (Claude Sonnet/Opus/Fable o Codex, con o sin modelo específico), **dónde van las notas de cierre** si el CLAUDE.md no lo dijo (dentro del repo — default, no hace falta Obsidian —, en una carpeta de tu vault, o ninguna) y, si elegiste Codex, el razonamiento. Funciona sin Obsidian, sin graphify y sin ningún otro skill: todo eso es opcional. Escribe **solo las claves que elegiste**: si para un rol te quedaste con el default, esa clave no se escribe y sigue al día con el plugin. Te avisa si implementador y revisor quedaron en el mismo modelo del mismo proveedor (perdés la mirada independiente), y cierra mostrando la tabla de `/orquesta:estado` para que veas qué quedó.

```
/orquesta:init          ← la primera vez que usás orquesta en un proyecto (si la config ya existe, no la toca)
/orquesta:doctor        ← después, siempre: valida el entorno con lo que quedó
/orquesta:estado        ← la tabla de enrutamiento con la fuente de cada valor
```

### Scripts que podés correr a mano

Todos viven en `plugins/orquesta/scripts/` (dentro del plugin instalado, bajo `~/.claude/plugins/`). Útiles para depurar o para usar el protocolo sin el arquitecto:

```powershell
pwsh -NoProfile -File Initialize-Orquesta.ps1 -Objetivo "..."               # crea .orquesta/ y el PLAN en planificando
pwsh -NoProfile -File Initialize-OrquestaConfig.ps1                         # lo mismo que /orquesta:init (config del proyecto)
pwsh -NoProfile -File Test-Brief.ps1 -Brief .orquesta/briefs/BRIEF-01.md    # valida la forma de un BRIEF
pwsh -NoProfile -File Show-Estado.ps1                                       # lo mismo que /orquesta:estado
pwsh -NoProfile -File Show-Costos.ps1 [-Sesion <id>] [-Json]                # lo mismo que /orquesta:costos (-Json para tu dashboard)
pwsh -NoProfile -File Marcar-Tarea.ps1 -Tarea 3 -Resultado APROBADO -Trabajador "implementador (sonnet)" -Intento 1 -Revisor "revisor (opus)" -Notas "..."
                                                                            # marca [x]/[~], fila en ## Bitácora de revisión y evento en bitacora.jsonl, en una llamada
pwsh -NoProfile -File Doctor-Orquesta.ps1                                   # lo mismo que /orquesta:doctor
pwsh -NoProfile -File Resolve-OrquestaConfig.ps1 -Pretty                    # la config efectiva ya mezclada
pwsh -NoProfile -File Invoke-Codex.ps1 -Rol implementador -Brief .orquesta/briefs/BRIEF-01.md -Intento 1
```

## 6. Configuración: qué modelo hace qué

La config se resuelve por **merge profundo** de tres archivos; solo escribís las claves que cambian:

1. `plugins/orquesta/config/orquesta.defaults.json` — los defaults del plugin (no lo edites).
2. `~/.claude/orquesta.json` — vos, para todos tus proyectos.
3. `<proyecto>/.claude/orquesta.json` — este proyecto (se versiona con el repo, así el equipo comparte el enrutamiento).

En la práctica alcanza con el archivo del proyecto: el global es opcional y no hace falta crearlo (sin él, los dos modelos son idénticos). Para crear el del proyecto sin escribirlo a mano, `/orquesta:init` deja un esqueleto mínimo, editable y pre-llenado desde tu `CLAUDE.md` (ver [§5](#orquestainit)). Si en algún momento no sabés de dónde sale un valor, `/orquesta:estado` lo dice archivo por archivo.

### Todas las claves

| Clave | Default | Qué controla |
|---|---|---|
| `orquestador.modelo` | `fable` | Modelo esperado para la sesión del arquitecto. Solo declara la expectativa: el modelo real lo fijás con `claude --model` o `/model`, y el aviso de "no coincide" lo da el arquitecto por autoconocimiento (best-effort; ningún script puede leer el modelo de la sesión). |
| `trabajadores.<rol>.modelo` | ver §7 | Con motor claude: `haiku`, `sonnet`, `opus`, `fable` (alias del Agent tool) o `inherit` (el modelo de la sesión, es decir el del arquitecto). Los IDs completos (`claude-sonnet-5`) no los acepta el Agent tool: usá alias (si ponés uno, el arquitecto lo reduce al alias que contiene y te avisa). Con motor codex: un modelo de Codex (`gpt-5.x`); vacío o alias de Claude → cae a `motores.codex.modelo`. |
| `trabajadores.<rol>.motor` | `claude` | `claude` (subagente) o `codex` (proceso `codex exec`). |
| `trabajadores.<rol>.esfuerzo` | según rol | Documentativo; el esfuerzo real está en el frontmatter del agente. |
| `motores.codex.comando` | `codex` | Ejecutable de Codex (o ruta a un `.ps1` para pruebas). |
| `motores.codex.modelo` | `""` | Modelo de Codex por defecto para trabajadores en codex que no tengan uno. |
| `motores.codex.razonamiento` | `high` | `low` / `medium` / `high` / `xhigh` → `-c model_reasoning_effort`. |
| `motores.codex.sandbox` | `workspace-write` | `read-only` / `workspace-write` / `danger-full-access`. |
| `motores.codex.salida_estructurada` | `true` | Pedir JSON según `schemas/` y renderizarlo a REPORTE/REVISIÓN. `false` = texto libre. |
| `motores.codex.args_extra` | `[]` | Flags adicionales para `codex exec`. |
| `enrutamiento.senior_si` | lista | Subcadenas en el título/descripción de una tarea que la mandan a `implementador-senior` (`migraci`, `oracle`, `concurren`, `azure function`, `key vault`…). |
| `enrutamiento.seguridad_si` | lista | Subcadenas que suman `auditor-seguridad` a la revisión (`sql`, `dapper`, `secret`, `auth`, `endpoint`, `input`…). |
| `enrutamiento.max_reintentos_por_tarea` | `2` | Rechazos del revisor antes de escalar de tier. |
| `limites.max_paralelo` | `3` | Trabajadores en paralelo. Más no acelera: te satura de reportes. |
| `limites.max_lineas_reporte` | `40` | Tope de un REPORTE; lo largo va a `.orquesta/reportes/`. |
| `limites.compuerta_delegacion_chars` | `1200` | Cualquier delegación con prompt ≥ esto exige PLAN aunque no sea a un trabajador de orquesta. |
| `contexto.graphify.usar` / `salida` / `actualizar_al_cerrar` | `true` / `graphify-out` / `true` | Dónde está el grafo y si se refresca al cerrar. |
| `contexto.obsidian.usar` | `true` | `false` apaga ADR/HANDOFF por completo: el arquitecto no delega al documentador, `/orquesta:estado`/`/orquesta:doctor` muestran "desactivado". |
| `contexto.obsidian.vault_root` | `""` | Ruta absoluta a tu vault. Va en `~/.claude/orquesta.json` (**personal**, nunca en el del proyecto). Ver [§13](#13-graphify-obsidian-y-la-documentación-que-deja). |
| `contexto.obsidian.carpeta_decisiones` / `carpeta_handoffs` / `prefijo_adr` / `prefijo_handoff` | `docs/decisiones` / `docs/handoffs` / `ADR-` / `HANDOFF-` | Dónde y cómo se nombran las notas. Si ya son una ruta absoluta, se usan tal cual; si no, y hay `vault_root`, se resuelven contra el vault; si no, contra el repo. |
| `rutas.raiz` / `plan` / `briefs` / `reportes` / `bitacora` | `.orquesta/...` | Ubicación de los artefactos en el proyecto. |
| `compuertas.delegacion` / `arquitecto_no_edita` / `cierre` / `bitacora` | `true` | Apagar compuertas individualmente. |

### Quién puede ser el arquitecto

El arquitecto es **siempre la sesión de Claude Code**. No es una preferencia: las compuertas son hooks de Claude Code, y es la sesión la que llama al Agent tool (trabajadores en `motor: claude`) o corre `Invoke-Codex.ps1` (trabajadores en `motor: codex`). Su modelo se fija con `claude --model <m>` o `/model <m>`, **no** en el JSON — `orquestador.modelo` solo declara cuál esperás para que el arquitecto te avise si arrancaste en otro.

Por lo mismo, **Codex no puede ser el arquitecto**. Sí puede ser cualquier trabajador: implementador, senior, revisor, auditor, documentador, cartógrafo (§8).

Los trabajadores, en cambio, se configuran libremente: `motor` (`claude` o `codex`) y `modelo` por rol. Regla práctica: el que **implementa** y el que **revisa** deberían ser modelos o proveedores distintos, y nunca el mismo proceso.

### Ejemplos de configuración listos para copiar

Van en `<proyecto>/.claude/orquesta.json` (este repo, se versiona) o en `~/.claude/orquesta.json` (vos, todos tus proyectos). Solo escribís las claves que cambian; lo demás sale de los defaults.

**A) Fable orquesta · subagentes de Claude implementan (Sonnet/Opus) y revisan (Opus)** — el default. No hace falta ningún archivo.

```
claude --model fable
/orquesta:arquitecto <objetivo>
```

Para la mayoría de los proyectos. El cartógrafo y el implementador van en Sonnet, senior/revisor/auditor en Opus, documentador en Sonnet.

**B) Fable orquesta · Codex implementa · Claude Opus revisa y audita** — revisión entre proveedores distintos: la combinación más valiosa, y la que más cuota de Claude ahorra sin perder rigor en la revisión.

```json
{
  "trabajadores": {
    "implementador":        { "motor": "codex" },
    "implementador-senior": { "motor": "codex" }
  },
  "motores": { "codex": { "razonamiento": "high" } }
}
```

Requiere `npm i -g @openai/codex` y `codex login`. El modelo de Codex es el de tu `~/.codex/config.toml`; para fijar uno concreto, `"implementador": { "motor": "codex", "modelo": "gpt-5.4" }` o, para todos los trabajadores en codex, `"motores": { "codex": { "modelo": "gpt-5.4" } }`. El archivo completo está en `ejemplos/orquesta-codex.json`.

**C) Fable orquesta · Codex hace todo lo que escribe y todo lo que revisa** — para cuidar la cuota de Claude al máximo: Fable solo planea, escribe briefs y aprueba.

```json
{
  "trabajadores": {
    "implementador":        { "motor": "codex" },
    "implementador-senior": { "motor": "codex" },
    "revisor":              { "motor": "codex" },
    "auditor-seguridad":    { "motor": "codex" }
  }
}
```

"Quien implementó no se revisa a sí mismo" se sigue cumpliendo: el revisor es **otro proceso** `codex exec`, con su propio estado y sin el hilo del implementador. Lo que perdés respecto a B es la mirada de un proveedor distinto sobre el código.

**D) Claude implementa · Codex revisa** — el espejo de B: segundo par de ojos de otro proveedor sobre lo que escribió Sonnet/Opus.

```json
{ "trabajadores": { "revisor": { "motor": "codex" } } }
```

**E) Opus como sesión (sin Fable) · Sonnet implementa y mapea** — cuando no tenés Fable o no querés gastarlo en planear. Declaralo para que el aviso de "modelo distinto al esperado" no aparezca:

```json
{ "orquestador": { "modelo": "opus" } }
```

Arrancá con `claude --model opus`. `implementador: sonnet` y `cartografo: sonnet` ya son default. Si además querés que el revisor no sea el mismo modelo que la sesión, `"revisor": { "modelo": "sonnet" }` o pasalo a Codex (D).

**F) Todo barato, para tareas triviales** — Sonnet como sesión, Haiku implementa, Sonnet revisa. Sirve para renombres, docs, tests mecánicos. Perdés juicio en el PLAN y rigor en la revisión: no lo uses para migraciones ni SQL.

```json
{
  "orquestador": { "modelo": "sonnet" },
  "trabajadores": {
    "implementador":        { "modelo": "haiku" },
    "implementador-senior": { "modelo": "sonnet" },
    "revisor":              { "modelo": "sonnet" },
    "auditor-seguridad":    { "modelo": "sonnet" }
  }
}
```

**¿Y "Codex orquesta, Claude implementa"?** No aplica en este plugin, por lo explicado arriba: el arquitecto es la sesión de Claude Code por diseño. Lo más cercano es **C** (Codex hace todo lo que escribe y revisa; Claude solo planea) o **D** (Claude escribe, Codex revisa).

**Ajustes que se combinan con cualquiera de los anteriores:**

```json
{
  "trabajadores": { "revisor": { "modelo": "fable" }, "auditor-seguridad": { "modelo": "fable" } },
  "limites": { "max_paralelo": 4 },
  "enrutamiento": { "senior_si": ["migraci", "oracle", "stored procedure", "pos_detalle"] },
  "contexto": { "obsidian": { "carpeta_decisiones": "docs/adr", "carpeta_handoffs": "docs/handoffs" } }
}
```

Fable como revisor es la máxima exigencia (cuidá la cuota). Verificá siempre con `/orquesta:estado`: muestra trabajador → motor → modelo y **de qué archivo sale cada valor**, y la línea "Obsidian: decisiones `<ruta>`" ya resuelta (ver §13 si usás un vault externo).

### Cambiar modelos desde el chat

Si en el chat decís "usá opus para todo" o "no gastes Fable en esto", eso manda **durante esa orquestación** y queda anotado en `## Enrutamiento → Overrides` del PLAN — el arquitecto no toca `.claude/orquesta.json` por su cuenta, porque es un archivo compartido y versionado con el proyecto.

Si la frase suena a preferencia permanente ("de ahora en más", "siempre en este proyecto", "cambialo para todos") en vez de puntual, el arquitecto te pregunta si lo persistís: en `.claude/orquesta.json` (este proyecto) o en `~/.claude/orquesta.json` (todos tus proyectos). Con tu confirmación, edita solo las claves que cambian — nunca reescribe el archivo entero. Sin confirmación explícita, queda como override de esa orquestación nada más. Si preferís no esperar la pregunta, seguís pudiendo editar el JSON vos mismo en cualquier momento.

Verificá siempre con `/orquesta:estado` (muestra de qué archivo sale cada valor) y, durante una corrida, con `/tasks` (muestra el modelo real de cada subagente).

## 7. Los trabajadores

| Trabajador | Modelo | Herramientas | Qué recibe | Qué devuelve |
|---|---|---|---|---|
| `orquesta:cartografo` | sonnet | solo lectura | el objetivo, o una tarea y sus archivos | Mapa ≤ 60 líneas: archivos clave, contratos copiados textuales con `archivo:línea`, convenciones, decisiones previas (Obsidian), pruebas, riesgos, preguntas que el repo no responde; marca `[inferido]` lo que no leyó. Segundo modo, "contratos para un BRIEF" (≤ 40 líneas): los fragmentos exactos que una tarea necesita, para que el arquitecto no abra el repo. |
| `orquesta:implementador` | sonnet | lee, edita, ejecuta | ruta del BRIEF, PLAN, intento | REPORTE ≤ 40 líneas. Alcance = BRIEF; `BLOQUEADO` antes que adivinar; nunca hace commit. |
| `orquesta:implementador-senior` | opus | lee, edita, ejecuta | igual + hallazgos del intento anterior | REPORTE. Especializado en dual-engine SQL Server/Oracle, migraciones con rollback, SPs, concurrencia, Azure Functions, Key Vault. |
| `orquesta:revisor` | opus | solo lectura + build/tests | BRIEF, REPORTE, intento | REVISIÓN: `APROBADO`/`RECHAZADO`, criterios con evidencia, hallazgos por severidad, decisiones del trabajador a ratificar. Único que cierra `[x]` y `V.`. |
| `orquesta:auditor-seguridad` | opus | solo lectura | archivos del cambio | AUDITORÍA: inyección SQL/comando/LDAP/log/path/SSRF, parametrización, `BindByName` en Oracle, errores que filtran, secretos fuera de Key Vault, menor privilegio. Precarga tu skill `security-injection-audit` si la tenés. |
| `orquesta:documentador` | sonnet | lee, escribe (no código) | PLAN cerrado, carpetas destino | ADR por decisión relevante + HANDOFF, con frontmatter y `[[wikilinks]]`; `graphify update .`. |

Cada rol está definido en `plugins/orquesta/agents/<rol>.md`. Ese mismo texto es el que recibe Codex cuando el trabajador corre en `motor: codex`, así el rol es idéntico en ambos motores.

`implementador`, `implementador-senior` y `revisor` tienen **memoria de agente a nivel proyecto**: aprenden convenciones, comandos de test y trampas del repo entre orquestaciones (Claude Code la guarda bajo `.claude/agent-memory/`).

**Escalado, siempre de ida:** `implementador → implementador-senior → el arquitecto parte la tarea en 2-3 briefs más finos → vuelve al senior`. El arquitecto nunca implementa al escalar: si el senior no pudo, el problema casi siempre está en el BRIEF.

Estos seis son **los únicos trabajadores que existen** — cada uno tiene un agente real en `agents/<rol>.md`; agregar un nombre distinto en la config no crea uno nuevo. Por cada uno elegís `motor` (`claude` o `codex`) y `modelo`; con `motor: claude` el **esfuerzo real está fijo en el agente** (no se configura desde el JSON: la clave `trabajadores.<rol>.esfuerzo` es solo informativa, para lo que muestran `/orquesta:estado` y el PLAN), con `motor: codex` el esfuerzo es la clave `motores.codex.razonamiento` — ver la salvedad en [§8](#8-codex-como-motor).

## 8. Codex como motor

Los subagentes de Claude Code solo corren modelos Claude, pero un trabajador de orquesta no tiene que ser un subagente: puede ser un proceso `codex exec` (el modo no interactivo de [Codex CLI](https://developers.openai.com/codex/noninteractive)).

### Configurar

```
npm i -g @openai/codex
codex login
```

y en `.claude/orquesta.json`:

```json
{
  "trabajadores": {
    "implementador":        { "motor": "codex" },
    "implementador-senior": { "motor": "codex" }
  },
  "motores": { "codex": { "sandbox": "workspace-write", "razonamiento": "high" } }
}
```

No hace falta poner `"modelo"`: si el trabajador no tiene un modelo de Codex (o tiene un alias de Claude heredado del default), se usa `motores.codex.modelo`, y si ese está vacío, el default de `~/.codex/config.toml`.

`/orquesta:doctor` confirma que encuentra `codex`, su versión y si estás logueado.

### Qué modelos de Codex podés poner en `modelo`

La lista cambia con el tiempo — esta es una foto de lo que había en `~/.codex/models_cache.json` al escribir esto (Codex CLI 0.144.6). Confirmá la vigente con `codex --help`, la carpeta `~/.codex/` o la [documentación de OpenAI](https://developers.openai.com/api/docs/guides/latest-model):

| `modelo` | Qué dice OpenAI que es | Para qué |
|---|---|---|
| `gpt-6-astra` | Su modelo más capaz para trabajo complejo y demandante | `implementador-senior`: migraciones, dual-engine, concurrencia |
| `gpt-reserve` | Código agéntico rápido y económico | trabajo en paralelo/background sin competir por capacidad |
| `gpt-5.6-sol` | Caballo de batalla confiable para tareas cotidianas | `implementador` estándar, alternativa a terra |
| `gpt-5.6-terra` | Balanceado para el trabajo diario | `implementador` estándar (suele ser el default de `~/.codex/config.toml`) |
| `gpt-5.6-luna` | Rápido y económico | triage barato, tareas de solo lectura si algún día pasás el cartógrafo a Codex |
| `gpt-5.5` | Generación anterior, "probada" | compatibilidad; no es el default recomendado |

**El `razonamiento` (`low`/`medium`/`high`/`xhigh`) es una sola clave global** en `motores.codex`, no por trabajador: si `implementador` e `implementador-senior` corren los dos en Codex, comparten el mismo nivel. Lo que sí es independiente por rol es el `modelo` — por eso la estrategia habitual es diferenciar por modelo (`gpt-5.6-terra` vs `gpt-6-astra`) y dejar el razonamiento en `high` para ambos, en vez de tratar de bajarlo para el implementador estándar.

### Qué pasa cuando una tarea va a Codex

El arquitecto no usa el Agent tool: corre `scripts/Invoke-Codex.ps1 -Rol implementador -Brief .orquesta/briefs/BRIEF-01.md -Intento 1` en segundo plano (Codex tarda minutos) y sigue con otras tareas. El wrapper:

1. Aplica **las mismas compuertas**: sin PLAN `en-ejecucion` (o `pausado`), sin BRIEF, o con BRIEF que no pasa `Test-Brief.ps1`, se niega con la razón por stderr y exit 2.
2. Arma el prompt **en la forma que OpenAI recomienda para GPT-5.x**: bloques `<role_instructions>` (el mismo `agents/<rol>.md` que usaría Claude), `<task>` con "terminado significa: cada criterio verificado con evidencia", `<default_follow_through_policy>`, `<action_safety>`, `<verification_loop>`, `<grounding_rules>` y el contrato de salida.
3. Ejecuta `codex exec --json --sandbox workspace-write -C <repo> -o <reporte> [-m modelo] -c model_reasoning_effort="high" --output-schema schemas/reporte.schema.json -` con el prompt por stdin.
4. Pide **salida estructurada**: JSON contra `schemas/reporte.schema.json` (implementadores) o `schemas/revision.schema.json` (revisor/auditor). Guarda el JSON crudo y lo **renderiza al mismo formato REPORTE/REVISIÓN** que producen los trabajadores de Claude. Si Codex devolviera texto en vez de JSON, cae al modo texto sin romper nada.
5. Registra en la bitácora agente, modelo, duración y **tokens** de Codex.
6. Guarda el `thread_id` de Codex y el rol que corrió. En un reintento del **mismo rol** (`-Intento 2 -Hallazgos <dictamen>`) usa `codex exec resume <thread_id>` para que Codex conserve el contexto del intento anterior; al **escalar** a `implementador-senior` arranca un hilo limpio (`-SinResume` lo fuerza también en el mismo rol). Los flags que `exec resume` acepta (`--json`, `-o`, `--output-schema`, `-m`, `-c`) van después del subcomando, y si `resume` no reescribe el archivo `-o`, el reporte se toma de los eventos JSONL en vez de reusar el del intento anterior.

Archivos que deja en `.orquesta/reportes/`: `REPORTE-01-codex.md` (renderizado), `REPORTE-01-codex.json` (crudo), `.codex-REPORTE-01.jsonl` (eventos), `.codex-REPORTE-01.log` (stderr) y `.codex-REPORTE-01.json` (estado: thread_id, intentos).

### Combinaciones útiles

Están con su JSON en [§6, ejemplos B, C y D](#ejemplos-de-configuración-listos-para-copiar): Codex implementa y Claude revisa (la más valiosa), Codex hace todo lo que escribe y revisa, o Claude implementa y Codex revisa.

Lo que no cambia: el arquitecto es siempre la sesión de Claude Code, el BRIEF es el contrato, y quien implementó no se revisa a sí mismo.

### Sandbox y red

`workspace-write` permite editar el repo pero **bloquea la red**. Si tu `dotnet restore` necesita bajar paquetes dentro de la corrida, restaurá antes de delegar o usá `"sandbox": "danger-full-access"` (solo en tu máquina, nunca en CI). `read-only` sirve para `-Rol revisor` o `-Rol cartografo`.

### Seguridad de la config

`motores.codex.comando`, `args_extra` y `sandbox` pueden venir del `.claude/orquesta.json` **del proyecto**, y ese archivo viaja con el repo: en un clon ajeno decide qué ejecutable corre el arquitecto y con qué permisos. Por eso `/orquesta:doctor` y `/orquesta:estado` lo marcan cuando el proyecto redefine alguna de las tres. Si el override es tuyo, movelo a `~/.claude/orquesta.json`; si el repo es de otro, leé ese archivo antes de delegar.

## 9. El PLAN

`.orquesta/PLAN.md` se crea con `Initialize-Orquesta.ps1` desde `plantillas/PLAN.md` y tiene esta forma:

```markdown
---
objetivo: Exportar cierres de caja a CSV
estado: en-ejecucion
creado: 2026-09-08
arquitecto: fable
rama: feature/reportes
---
# PLAN — Exportar cierres de caja a CSV

## Clarificado
- Q1: ¿descarga desde pantalla o job? -> descarga desde la pantalla de cierres
- Rama: feature/reportes (actual)

## Contexto (del cartógrafo)
- src/Cierres/CierreService.cs — consultas actuales vía IDbExecutor
- tests/Cierres.Tests — xUnit, se corre con dotnet test --filter Cierres

## Decisiones
- D1: endpoint GET /api/cierres/export — por qué: reutiliza auth existente — descartado: job nocturno
- D2: rango máximo 92 días → 400 — por qué: evita exportaciones gigantes

## Enrutamiento
| Trabajador | Motor | Modelo | Cuándo |
|---|---|---|---|
| orquesta:implementador | claude | sonnet | Implementación estándar |
Overrides de esta sesión: ninguno.

## Tareas
- [x] 1. Servicio ICierreExportService — tier: implementador — brief: briefs/BRIEF-01.md — depende: —
- [ ] 2. Endpoint + validación de rango — tier: implementador — brief: briefs/BRIEF-02.md — depende: 1
- [ ] 3. Consulta dual-engine — tier: implementador-senior — brief: briefs/BRIEF-03.md — depende: —
- [~] 4. Envío por correo — diferido con aprobación del usuario (fuera de alcance)
- [ ] V. Verificación final (build + tests + criterios de todos los briefs) — revisor

## Bitácora de revisión
| # | Trabajador (modelo) | Intento | Revisor | Resultado | Notas |
|---|---|---|---|---|---|
| 1 | implementador (sonnet) | 1 | revisor (opus) | APROBADO | |
```

### Estados

| `estado:` | Significa | Compuertas |
|---|---|---|
| `planificando` | El PLAN existe pero no lo aprobaste. | No se delega implementación. |
| `en-ejecucion` | Aprobado; se está delegando y revisando. | Todas activas: el arquitecto no edita código; no se cierra el turno con `[ ]` sin explicación. |
| `pausado` | Esperando una decisión tuya, o un ajuste trivial que autorizaste hacer a mano. | Relajadas. |
| `cerrado` | Verificación final aprobada y documentación hecha. | Para trabajo nuevo, archivá este PLAN (`PLAN-<tema>-archivo.md`) e iniciá otro. |

Podés editar el PLAN a mano: es Markdown. Las compuertas leen `estado:` del frontmatter y las marcas `- [ ]` bajo `## Tareas`.

**PLAN y briefs se versionan** (son la trazabilidad); `bitacora.jsonl` y los marcadores de sesión no (`.orquesta/.gitignore` ya lo excluye).

## 10. El BRIEF

Un BRIEF es bueno cuando un trabajador que **no vio nada** de la conversación puede terminarlo sin preguntar, y el revisor puede aprobarlo sin interpretar. Anatomía (`plantillas/BRIEF.md`):

````markdown
---
brief: BRIEF-02
tarea: "2. Endpoint + validación de rango"
tier: implementador
modelo: sonnet
intento: 1
---
# BRIEF-02 — Endpoint de exportación CSV

## Contexto mínimo
API de cierres en `Cierres.Api` (.NET 10, controladores, auth por política `Cierres.Leer`).
Existe `ICierreExportService.ExportarCsvAsync` (BRIEF-01). Convenciones en CLAUDE.md.

## Objetivo de la tarea
Exponer GET /api/cierres/export?desde&hasta que devuelve el CSV como archivo.

## Archivos
- Leer primero: `src/Cierres.Api/Controllers/CierresController.cs`, `src/Cierres/ICierreExportService.cs`
- Modificar: `src/Cierres.Api/Controllers/CierresController.cs`
- Crear: `tests/Cierres.Api.Tests/CierresExportEndpointTests.cs`
- NO tocar: `src/Cierres/**` (es de BRIEF-01 y BRIEF-03)

## Contrato exacto
```csharp
[HttpGet("export")]
[Authorize(Policy = "Cierres.Leer")]
public async Task<IActionResult> Export([FromQuery] DateOnly desde, [FromQuery] DateOnly hasta, CancellationToken ct)
// 400 con ProblemDetails "Rango máximo 92 días" si (hasta - desde) > 92
// 200 text/csv; charset=utf-8, Content-Disposition: attachment; filename="cierres_{desde:yyyyMMdd}_{hasta:yyyyMMdd}.csv"
```

## Criterios de aceptación (verificables)
1. Rango válido devuelve 200 con `Content-Type: text/csv` — test `CierresExportEndpointTests.RangoValido_Devuelve200Csv`.
2. Rango > 92 días devuelve 400 con ProblemDetails — test `...RangoExcedido_Devuelve400`.
3. Sin la política `Cierres.Leer` devuelve 403 — test `...SinPermiso_Devuelve403`.
4. `dotnet build src/Cierres.sln -warnaserror` limpio y `dotnet test --filter CierresExportEndpointTests` en verde.

## Restricciones
- No cambiar firmas públicas fuera de las listadas. No agregar paquetes NuGet (proponer como PROPUESTA).
- No tocar la capa de datos.

## Cómo verificar
```powershell
dotnet build src/Cierres.sln -warnaserror
dotnet test tests/Cierres.Api.Tests --filter CierresExportEndpointTests
```

## Formato del reporte
REPORTE, máx 40 líneas; detalle largo a `.orquesta/reportes/REPORTE-02.md`.
````

### Lo que la compuerta exige (y `Test-Brief.ps1` comprueba)

- `## Criterios de aceptación` con **≥ 2 ítems numerados concretos** (no `…`, no "que funcione bien").
- `## Cómo verificar` con **al menos un comando** dentro de un bloque de código.
- Una línea **`NO tocar:`** (puede ser `NO tocar: nada`; obliga a pensar en los conflictos con tareas paralelas).
- Sin marcadores de la plantilla (`BRIEF-NN`, `<título>`).

```
> pwsh -NoProfile -File Test-Brief.ps1 -Brief .orquesta/briefs/BRIEF-02.md
BRIEF: .orquesta/briefs/BRIEF-02.md
  criterios numerados concretos: 4 ✓
  comandos en 'Cómo verificar': 2 ✓
  línea 'NO tocar':              ✓
  sin marcadores de plantilla:   ✓
Resultado: VÁLIDO — se puede delegar.
```

### Errores típicos que producen rechazos

1. **Contrato descrito en vez de copiable** → el trabajador elige otros nombres y la siguiente tarea no encaja.
2. **Criterio no verificable** ("es limpio", "sigue buenas prácticas") → el revisor no puede aprobar y la tarea rebota sin culpa del trabajador.
3. **Dependencia oculta** → la tarea necesita algo que otra aún no entregó; en el PLAN va como `depende:`.
4. **Alcance abierto** → el trabajador "aprovecha" y toca archivos de otra tarea paralela.
5. **Tests inexistentes** → pedís `dotnet test` en un proyecto sin proyecto de tests.
6. **Brief gigante** → si pasa de ~120 líneas, son dos tareas.

La checklist completa está en `skills/arquitecto/referencias/brief-checklist.md`.

## 11. REPORTE y REVISIÓN

### REPORTE (lo devuelve el trabajador)

```markdown
# REPORTE — BRIEF-02 (intento 1)
**Estado:** COMPLETADO

## Cambios
- `src/Cierres.Api/Controllers/CierresController.cs` — acción Export con validación de rango
- `tests/Cierres.Api.Tests/CierresExportEndpointTests.cs` — 3 tests

## Criterios de aceptación
1. ✓ 200 text/csv — evidencia: RangoValido_Devuelve200Csv en verde
2. ✓ 400 ProblemDetails — evidencia: RangoExcedido_Devuelve400 en verde
3. ✓ 403 sin permiso — evidencia: SinPermiso_Devuelve403 en verde
4. ✓ build -warnaserror y tests — evidencia: 3 pasaron, 0 fallaron

## Pruebas ejecutadas
- `dotnet test tests/Cierres.Api.Tests --filter CierresExportEndpointTests` → 3 pasaron

## Dudas / riesgos
- El nombre de archivo usa la zona horaria del servidor; ¿debería ser la del usuario?

## Propuestas (no aplicadas)
- PROPUESTA: cachear la política de autorización en el controlador base.
```

Estados posibles: `COMPLETADO`, `PARCIAL` (falta algo de esta tarea: el arquitecto lo devuelve al mismo agente antes de revisar), `BLOQUEADO` (con la pregunta exacta).

### REVISIÓN (lo devuelve el revisor)

```markdown
## REVISIÓN — BRIEF-02 (intento 1)
**Dictamen:** RECHAZADO
### Criterios
1. ✓ 200 text/csv — evidencia: test en verde (lo corrí)
2. ✗ 400 ProblemDetails — evidencia: el test pasa, pero el body no es ProblemDetails (CierresController.cs:48 devuelve BadRequest(string))
### Hallazgos
- [Debe] Respuesta 400 sin ProblemDetails — `CierresController.cs:48` → usar `Problem(...)`.
- [Sugerencia] El filename no escapa caracteres — `CierresController.cs:61`.
### Comandos ejecutados
- `dotnet test … --filter CierresExportEndpointTests` → 3 pasaron
### Para el arquitecto
- El trabajador asumió zona horaria del servidor: ratificar o revertir.
```

`APROBADO` exige todos los criterios ✓ y ningún `[Crítico]` ni `[Debe]` abierto. Si el BRIEF tenía criterios no verificables, el revisor lo dice: es un defecto del BRIEF.

Cuando el trabajador o el revisor corren en Codex, el JSON estructurado se renderiza exactamente a estos formatos, con un dato extra: la **confianza** (0-1) de cada hallazgo.

## 12. Las compuertas

| Compuerta | Evento | Dispara cuando | Cómo se destraba |
|---|---|---|---|
| **Aviso de sesión** | `SessionStart` | Abrís, reanudás o compactás una sesión en un proyecto con PLAN abierto. | No bloquea: le recuerda a Claude el estado y las tareas abiertas, y a vos te muestra una línea. |
| **Delegación** | `PreToolUse(Agent)` | Se delega a `implementador*`/`documentador` (o cualquier prompt ≥ 1200 chars) sin PLAN, con PLAN `planificando`/`cerrado`, con BRIEF inexistente, o con BRIEF que no pasa la validación de forma. Un brief inline se acepta solo con criterios numerados. | PLAN `en-ejecucion` + BRIEF válido. `cartografo`, `revisor`, `auditor`, `Explore`, `Plan` y `fork` nunca se gobiernan. `Invoke-Codex.ps1` aplica la misma regla. |
| **El arquitecto no edita** | `PreToolUse(Edit\|Write)` | PLAN `en-ejecucion` y el hilo principal (no un subagente) escribe fuera de `.orquesta/`, `.claude/`, `docs/`, carpetas de Obsidian o `*.md`. | Delegar, o `estado: pausado` para un ajuste trivial autorizado. |
| **Cierre** | `Stop` | PLAN `en-ejecucion` con tareas `[ ]` al terminar el turno. **Una vez por sesión.** | Seguir, diferir `[~]` con tu OK, o `estado: pausado` si el arquitecto espera tu respuesta. |
| **Bitácora** | `SubagentStop` | Siempre: registra tipo, tamaño y estado del reporte. Si pasa 1.5× el límite, le pide al trabajador resumir. | — |

### Cuando una compuerta bloquea, el arquitecto ve la razón

```
orquesta: el PLAN está en 'estado: planificando'. Presentá el plan al usuario; cuando lo apruebe,
cambiá a 'estado: en-ejecucion' en .orquesta/PLAN.md y volvé a delegar.

orquesta: BRIEF-03 no pasa la validación de forma: '## Criterios de aceptación' necesita al menos 2
ítems numerados y concretos (hay 1) · falta la línea 'NO tocar:'. Corregilo (...) y volvé a delegar.

orquesta: PLAN en ejecución — el arquitecto no edita código (src/Cierres/CierreService.cs). Delegá este
cambio a orquesta:implementador con un BRIEF. Si es un ajuste trivial y el usuario lo autoriza, poné
'estado: pausado', hacé el cambio y volvé a 'en-ejecucion'.
```

### Apagarlas

- Una compuerta: `"compuertas": { "arquitecto_no_edita": false }` en la config.
- Toda la sesión: variable de entorno `ORQUESTA_GATES=0` antes de abrir Claude Code.
- Momentáneamente: `estado: pausado` en el PLAN.

Las compuertas verifican **forma**, no fidelidad: que exista un BRIEF con criterios, no que los criterios sean buenos. Eso lo cubre el revisor. Sin `pwsh` en el PATH, Claude Code muestra un aviso no bloqueante y el protocolo sigue solo por instrucciones.

## 13. graphify, Obsidian y la documentación que deja

### graphify (entrada)

Si existe `graphify-out/` (lo genera `/graphify .`), el cartógrafo lee `GRAPH_REPORT.md` o `wiki/index.md` y corre `graphify query "<objetivo>"` antes de tocar el código. Es más barato y más preciso que grep. Si hay `graphify-out/needs_update`, te avisa que el grafo está viejo; al cerrar, el documentador corre `graphify update .` (`contexto.graphify.actualizar_al_cerrar`). Sin grafo, el cartógrafo trabaja con Glob/Grep y `/orquesta:estado` te sugiere generarlo.

### Obsidian (salida)

Al cerrar un PLAN, el documentador escribe en las carpetas configuradas (por defecto `docs/decisiones` y `docs/handoffs`, dentro del repo).

**Si tu vault está fuera del repo**, lo más simple es la **ruta absoluta** en `contexto.obsidian.carpeta_decisiones`/`carpeta_handoffs` del `.claude/orquesta.json` del proyecto — es lo que escribe `/orquesta:init` (la toma tal cual del CLAUDE.md). Funciona en tu máquina y no hace falta nada más.

**Si el repo lo comparte un equipo** y no querés una ruta personal de tu disco en el archivo versionado (cada persona tiene el vault en otro lado), separalo en dos:

1. En tu `~/.claude/orquesta.json` **personal** (nunca en el del proyecto), declarás dónde está tu vault:
   ```json
   { "contexto": { "obsidian": { "vault_root": "C:\\_RoyRojas\\ObsidianVault\\Cerebro" } } }
   ```
2. En el `.claude/orquesta.json` **del proyecto** (compartible, no expone tu disco), declarás la subcarpeta relativa a *cualquier* vault:
   ```json
   { "contexto": { "obsidian": { "carpeta_decisiones": "Proyectos/MiProyecto/Decisiones", "carpeta_handoffs": "Proyectos/MiProyecto/Decisiones" } } }
   ```

`carpeta_decisiones`/`carpeta_handoffs` se resuelven así: si ya son una ruta absoluta, se usan tal cual; si no, y hay `vault_root` seteado, se resuelven contra el vault; si no hay ninguno de los dos, contra el repo (el default). **Ojo:** la forma relativa (`Proyectos/X/Decisiones`) solo tiene sentido con `vault_root`; sin él se resuelve contra el repo y apunta a una carpeta que no existe. Si el CLAUDE.md del proyecto declara otra carpeta que la que resuelve la config, `/orquesta:doctor` y `/orquesta:estado` te lo marcan. Así cada persona en el equipo apunta a su propio vault sin tocar el archivo compartido, y alguien sin vault de Obsidian simplemente sigue usando `docs/decisiones` dentro del repo. `contexto.obsidian.usar: false` apaga esto por completo (el arquitecto ni delega al documentador).

Tu vault no tiene por qué separar "Handoffs" de "Decisiones": si tu estructura solo tiene una carpeta de decisiones (por ejemplo la que arma el skill `configurar-proyecto`, con `Decisiones/` y `Hallazgos/`, sin `Handoffs/`), apuntá `carpeta_handoffs` a la misma carpeta que `carpeta_decisiones` — se distinguen igual por el prefijo del nombre de archivo (`ADR-` vs `HANDOFF-`).

**Sin escribir nada a mano:** si tu `CLAUDE.md` ya tiene la sección "Memoria del proyecto (Obsidian)" con `- Decisiones: <ruta absoluta>` (es lo que deja `configurar-proyecto`), `/orquesta:init` la lee **una vez** al crear la config del proyecto y pre-llena `carpeta_decisiones`/`carpeta_handoffs` con esa misma carpeta. Es la vía recomendada si preferís un archivo por proyecto: explícito, editable, y no tenés que tipear la ruta. Si la línea está abreviada (`...\Proyectos\X\Decisiones`) o no es absoluta, init no la copia y quedan los defaults — nunca adivina.

**`docs/decisiones/ADR-20260908-export-csv-cierres.md`**
```markdown
---
tipo: adr
titulo: "Exportación CSV de cierres por endpoint"
proyecto: "Cierres"
fecha: 2026-09-08
estado: aceptada
arquitecto: fable
tags: [adr, orquesta, cierres, csv]
---
# ADR — Exportación CSV de cierres por endpoint
## Contexto … ## Decisión … ## Alternativas consideradas … ## Consecuencias …
## Trazabilidad
- Plan: [[PLAN — Exportar cierres de caja a CSV]] · Briefs: BRIEF-01 … BRIEF-04
- Verificación: aprobada por orquesta:revisor el 2026-09-08 · Handoff: [[HANDOFF-20260908-export-csv-cierres]]
```

**`docs/handoffs/HANDOFF-20260908-export-csv-cierres.md`**: qué se entregó, cómo se verificó, decisiones clave (enlaza al ADR), lo diferido y por qué, cómo continuar, y el costo de la orquestación (delegaciones por modelo).

Un ADR por decisión que cambie contratos, datos, infraestructura o convenciones; las triviales van juntas en el HANDOFF. Si tu vault tiene otra estructura, cambiá las carpetas y prefijos en `.claude/orquesta.json`.

## 14. Bitácora y métricas

`.orquesta/bitacora.jsonl` (no versionado) recibe una línea JSON por evento:

```json
{"evento":"spawn","agente":"implementador","modelo":"sonnet","chars_prompt":412,"descripcion":"BRIEF-01","ts":"2026-09-08T14:02:11-06:00"}
{"evento":"stop","agente":"implementador","agent_id":"a1b2","lineas_reporte":31,"estado":"COMPLETADO","ts":"…"}
{"evento":"spawn","agente":"implementador-senior","motor":"codex","modelo":"codex-default","descripcion":"REPORTE-03 intento 1","ts":"…"}
{"evento":"stop","agente":"implementador-senior","motor":"codex","estado":"COMPLETADO","tokens_in":48213,"tokens_out":3120,"segundos":212,"estructurado":true,"ts":"…"}
```

`/orquesta:estado` la resume como "implementador [sonnet]: 6 · revisor [opus]: 6 · implementador-senior [codex]: 2". Con eso calibrás el enrutamiento: si la mitad de las tareas de SQL en Sonnet vuelven rechazadas, agregá `sql` a `senior_si`. Los tokens de los subagentes de Claude no vienen en la bitácora (Claude Code no los expone al hook); los de Codex sí. Desde 1.4.0 hay un tercer evento, `tarea` (lo escribe `Marcar-Tarea.ps1` por cada dictamen: tarea, resultado, trabajador, intento, revisor, notas), y el campo `sesion` de los eventos de hooks es lo que `/orquesta:costos` usa para encontrar los transcripts.

### Costos medidos, no estimados

Los tokens reales están en los transcripts de Claude Code: `~/.claude/projects/<proyecto>/<sesión>.jsonl` (la sesión del arquitecto) y `<sesión>/subagents/agent-<id>.jsonl` (uno por subagente). Cada respuesta del modelo trae `usage` con `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` y `output_tokens`. `/orquesta:costos` (`Show-Costos.ps1`) los agrega por actor y modelo y los valora con `costos.tarifas`.

Lo que enseñó la primera orquestación real medida (5 tareas, arquitecto Fable, 24 delegaciones):

| | Estimado a ojo | Medido |
|---|---|---|
| Requests del arquitecto | ~70 | 118 |
| Contexto del arquitecto | 200–250k | creció a 453k, sin compactar |
| Salida del arquitecto | 50k | 171k (el thinking se factura como salida) |
| Costo del arquitecto | $8–10 | $22–25 |
| Subagentes de Claude | $6 | $17,8 |

- **El costo del arquitecto es requests × contexto + salida.** Cada tool call es un request que relee todo el contexto desde caché; 58 Edits de registro y 9 "¿cómo vamos?" con Bash costaron ~$8–10 solos. De ahí `Marcar-Tarea.ps1` (una llamada por dictamen) y las reglas de "Economía de contexto" del skill.
- **Cambiar de modelo no ahorra**: con Opus la misma sesión habría costado casi lo mismo, porque su lectura de caché cuesta el doble que la de Fable. Bajar requests y contexto sí ahorra.
- **Reanudar una sesión larga para una tarea lateral es carísimo**: escribir la retro al día siguiente costó $10–14 (un request frío re-escribió 419k de caché, y un `/model` posterior lo repitió). Por eso retro, memoria y cierre van al documentador o a una sesión nueva.
- **El recon propio fue el 38 % del costo** porque el mapa de Haiku no traía contratos. Por eso el cartógrafo pasó a Sonnet con un modo "contratos para un BRIEF".
- **Una skill ajena que se disparó sola** metió 30k tokens al contexto del arquitecto y se releyó ~80 veces. Por eso el arquitecto no invoca otras skills durante la orquestación.

## 15. Recetas para situaciones comunes

**Solo quiero que revisen mi cambio, sin orquestar.**
`/orquesta:revisar` (diff actual) o `/orquesta:revisar src/Carpeta/`. No abre PLAN.

**Retomar lo que dejé ayer.**
Abrí Claude Code en el proyecto; el aviso de sesión te dice el estado. `/orquesta:arquitecto` sin argumento reanuda.

**Cambiar de modelo a mitad de una orquestación.**
Decilo en el chat ("desde ahora usá opus para implementar"); queda anotado en el PLAN. O editá `.claude/orquesta.json` y `/orquesta:estado` para confirmar.

**Un trabajador quedó BLOQUEADO con una pregunta que es mía.**
El arquitecto pone `estado: pausado`, te pregunta, y al responder actualiza el BRIEF y reenvía al mismo agente.

**Quiero hacer un arreglo de una línea yo mismo, con PLAN en ejecución.**
Pedíselo al arquitecto: pone `estado: pausado`, lo hace (o lo hacés vos), vuelve a `en-ejecucion`.

**Dos tareas tocan el mismo archivo.**
No las paralelices: en el PLAN, la que define el contrato va primero y sola; las que lo consumen después. La línea `NO tocar:` de cada BRIEF evita el 80 % de los conflictos.

**El proyecto no tiene graphify.**
Funciona igual (Glob/Grep). Cuando puedas, `/graphify .` en la raíz: el cartógrafo se vuelve más barato y más preciso.

**Un colega en Mac quiere instalarlo.**
`brew install powershell`, y el resto igual. Los scripts son PowerShell 7 multiplataforma; la CI corre en Ubuntu.

**Quiero probar el protocolo sin gastar en el arquitecto.**
`claude --model sonnet` y `/orquesta:arquitecto`. El arquitecto te avisará una vez que no está en el modelo configurado y seguirá. Para tareas serias volvé a Fable/Opus: el arquitecto es donde el juicio importa.

**Terminó todo pero no quiero cerrar hoy.**
Dejalo en `en-ejecucion` con las tareas `[x]`; mañana `/orquesta:revisar final` y el cierre.

## 16. Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Las compuertas no hacen nada; Claude Code muestra "hook error" | `pwsh` no está en el PATH que ve Claude Code, o es PowerShell 5.1 | `/orquesta:doctor`. Instalá PowerShell 7 y reabrí la terminal/Claude Code. |
| `/orquesta:arquitecto` aborta con un error de comando al arrancar | La inyección dinámica (`Show-Estado.ps1`) falló: sin `pwsh` o config inválida | `/orquesta:doctor`; validá `.claude/orquesta.json` como JSON. |
| "no existe .orquesta/PLAN.md" al delegar | El arquitecto quiso delegar antes de crear/aprobar el PLAN | Es la compuerta funcionando. Que cree el PLAN y te lo presente. |
| "BRIEF-NN no pasa la validación de forma" | Criterios vagos, sin comandos o sin `NO tocar:` | `Test-Brief.ps1 -Brief …` muestra qué falta. |
| Los subagentes no corren en el modelo configurado | `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` en tu entorno pisa todo, o la config no se está leyendo | `/orquesta:estado` (fuente de cada valor), `/tasks` (modelo real). Quitá la variable. |
| Codex: "not logged in" o `codex` no encontrado | Falta `codex login` o `codex` no está en PATH | `/orquesta:doctor`; `codex login` (o `codex login --device-auth`). |
| Codex devolvió texto en vez de JSON | El modelo/versión no respetó `--output-schema` | El wrapper cae a texto automáticamente. Si es recurrente, `"salida_estructurada": false`. |
| Codex falla en `dotnet restore` | El sandbox `workspace-write` bloquea la red | Restaurá antes de delegar, o `"sandbox": "danger-full-access"` en tu máquina. |
| Codex en Windows reporta `BLOQUEADO` con `CreateProcessWithLogonW failed` en el log | El sandbox `workspace-write` de Codex no puede anidarse dentro del propio sandbox de Claude Code en Windows | Probá `"sandbox": "danger-full-access"` en tu máquina (nunca en CI). Confirmado: con eso el mismo BRIEF corrió bien. |
| Codex: "not inside a trusted directory / git repo" | El proyecto no es un repo git | El wrapper agrega `--skip-git-repo-check`; mejor `git init`. |
| El aviso de sesión no aparece | El PLAN está `cerrado` o no existe | Es el comportamiento esperado. |
| Claude Code pregunta "Command spawns a nested PowerShell process which cannot be validated" cuando el arquitecto corre un script del plugin | Regla de seguridad de Claude Code: la herramienta PowerShell lanzando `pwsh` es un shell anidado que no puede validar contra las reglas de permiso, aunque el skill lo tenga permitido | Es normal. Elegí "Yes, and don't ask again" una vez por script. Los comandos `/orquesta:*` que solo muestran algo (doctor, estado) no preguntan: corren vía el `!` del skill. Con `Marcar-Tarea.ps1` los argumentos cambian en cada llamada: aceptá con "always allow" la primera vez y las siguientes pasan por prefijo. |
| El prompt de permiso muestra una ruta de `claude-orquesta` (el repo del plugin), no de mi proyecto | El marketplace es local (`source: directory`): Claude Code sirve el plugin desde su carpeta fuente, y `${CLAUDE_PLUGIN_ROOT}` apunta ahí | Es normal; no está tocando tu proyecto, es el plugin ejecutando su propio script. Con un marketplace de GitHub la ruta sería la caché de `~/.claude/plugins/`. |
| `/orquesta:estado` o `/orquesta:doctor` dicen "(no existe aún)" de una carpeta de Obsidian que sí existe en tu vault | No configuraste `contexto.obsidian.vault_root`, así que `carpeta_decisiones`/`carpeta_handoffs` se resuelven contra el repo (el default), no contra tu vault | Poné `vault_root` en tu `~/.claude/orquesta.json` **personal** (nunca en el del proyecto) — ver [§13](#13-graphify-obsidian-y-la-documentación-que-deja). |
| La delegación falla con un error de validación del parámetro `model` | Configuraste un ID completo (`claude-sonnet-5`) y el arquitecto lo pasó tal cual (plugin anterior a 1.3.1) | El Agent tool solo acepta `haiku`/`sonnet`/`opus`/`fable`. Desde 1.3.1 el arquitecto lo reduce al alias y omite `model:` con `inherit`; actualizá el plugin y, mejor, usá alias en la config. |
| El badge del README sale gris | El workflow no corrió aún o el nombre del repo cambió | Mirá la pestaña Actions. |

## 17. Convivencia con el plugin oficial de OpenAI

[`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) (`/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex`) es un puente hacia Codex: revisión nativa (`/codex:review`), revisión adversarial (`/codex:adversarial-review`), tareas en background, transferencia de sesión. **No orquesta nada**, así que no compite con orquesta: se complementan.

Recomendado tenerlo instalado: `/codex:review` antes de un commit, y `/codex:adversarial-review --base <rama>` como revisión de diseño de otro proveedor antes de la verificación final de un PLAN (el arquitecto te lo propone en el cierre si detecta el plugin). `/orquesta:doctor` te dice si está instalado.

## 18. Estructura del repo, pruebas y contribuir

```
Claude-Orquesta/
├── .claude-plugin/marketplace.json     ← el repo es un marketplace: /plugin marketplace add royrojas/Claude-Orquesta
├── .github/workflows/tests.yml         ← suite en windows-latest + ubuntu-latest en cada push
└── plugins/orquesta/
    ├── .claude-plugin/plugin.json
    ├── skills/
    │   ├── arquitecto/    SKILL.md (protocolo) · referencias/ (enrutamiento, brief-checklist, revision-checklist) · plantillas/ (PLAN, BRIEF, REPORTE, ADR, HANDOFF)
    │   ├── revisar/       SKILL.md (context: fork → orquesta:revisor)
    │   ├── estado/        SKILL.md
    │   ├── costos/        SKILL.md (Show-Costos: costo medido por actor y modelo)
    │   └── doctor/        SKILL.md
    ├── agents/            cartografo · implementador · implementador-senior · revisor · auditor-seguridad · documentador
    ├── hooks/hooks.json   las 5 compuertas → scripts/*.ps1
    ├── scripts/           OrquestaCommon.ps1 · Gate-Delegacion · Gate-Edicion · Gate-Cierre · Log-Delegacion · Aviso-Sesion · Show-Estado · Doctor-Orquesta · Resolve-OrquestaConfig · Initialize-Orquesta · Test-Brief · Invoke-Codex · Marcar-Tarea · Show-Costos
    ├── schemas/           reporte.schema.json · revision.schema.json
    ├── config/orquesta.defaults.json
    ├── ejemplos/          orquesta.json · orquesta-codex.json
    ├── tests/             Test-Orquesta.ps1 (251 aserciones) · fake-codex.ps1
    ├── README.md          ficha técnica del plugin
    └── CHANGELOG.md
```

### Pruebas

```powershell
pwsh -NoProfile -File plugins/orquesta/tests/Test-Orquesta.ps1
```

Sin dependencias (ni Pester). Valida JSON de manifiestos y hooks, frontmatter de agentes y skills, sintaxis de todos los scripts, merge de config, y cada compuerta alimentada con el JSON que Claude Code manda por stdin (deny/allow/block, `agent_id`, `stop_hook_active`, `ORQUESTA_GATES`), más el motor Codex contra un `codex` falso (compuertas, flags, prompt XML, `--output-schema`, JSON → REPORTE, thread_id, resume, tokens), la validación de BRIEFs, el aviso de sesión y el doctor. GitHub Actions corre lo mismo en Windows y Ubuntu en cada push.

### Contribuir

- Nuevo rol: `agents/<rol>.md` con frontmatter (`name`, `description`, `tools`, `model`) + entrada en `trabajadores` de `config/orquesta.defaults.json` + aserción en el test (cuenta de agentes).
- Nuevo motor: `Invoke-Codex.ps1` es el modelo a seguir; la config vive en `motores.<nombre>`.
- Cambios en compuertas: agregá el caso al `Test-Orquesta.ps1` con el JSON de entrada que Claude Code mandaría.
- Todo en español, con `vos`; scripts PowerShell 7 sin dependencias; sin backticks Markdown dentro de strings con comillas dobles de PowerShell (es carácter de escape).

## Changelog

El detalle por versión vive en [`plugins/orquesta/CHANGELOG.md`](plugins/orquesta/CHANGELOG.md).

### 2026-09-16 — 1.4.1: ningún skill de orquesta se activa solo
- El arquitecto ya no arranca por su cuenta cuando hablás de subagentes, delegar o "modo arquitecto": solo corre con `/orquesta:arquitecto`. Los seis skills llevan `disable-model-invocation: true`.
- Evita PLANes y delegaciones que no pediste; el modelo de la sesión trabaja directo hasta que lo invocás.

### 2026-09-16 — 1.4.0: costos medidos, registro en una llamada y economía de contexto
- Nuevo `/orquesta:costos` (`Show-Costos.ps1`): cuánto costó la orquestación leyendo el `usage` real de los transcripts de Claude Code y los tokens de Codex, por actor y modelo, con tarifas editables en `costos.tarifas`.
- Nuevo `Marcar-Tarea.ps1`: el arquitecto registra cada dictamen con una sola llamada en vez de editar el PLAN a mano varias veces.
- El skill arquitecto incorpora las reglas de "Economía de contexto" que salieron de medir una orquestación real: el arquitecto gastó más que todos sus subagentes juntos por cantidad de requests y tamaño de contexto, no por el modelo.
- El cartógrafo pasa a Sonnet y devuelve contratos textuales; el documentador puede escribir la retrospectiva para que no la haga el arquitecto al final de una sesión larga.

### Licencia

MIT — Roy Rojas.
