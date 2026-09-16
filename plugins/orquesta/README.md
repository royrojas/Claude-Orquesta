# orquesta — Claude como arquitecto, subagentes como implementadores

> **Manual completo (conceptos, tutorial paso a paso, configuración, Codex, BRIEFs, compuertas, recetas y solución de problemas):** [README del repositorio](../../README.md). Este archivo es la ficha técnica del plugin.

Plugin de Claude Code que separa **pensar** de **hacer**: el modelo principal (Fable o Opus) clarifica, diseña, escribe el plan y los briefs, y **revisa** cada entrega; subagentes con el modelo que vos configurás (Haiku/Sonnet/Opus) implementan. Cinco compuertas (hooks) hacen cumplir el protocolo para que no dependa de que el modelo "se acuerde".

```
 vos ──► /orquesta:arquitecto "objetivo"
              │
              ├─ 1. cartógrafo (haiku)   lee graphify + Obsidian + repo → mapa
              ├─ 2. clarificar           una sola ronda de preguntas, todas juntas
              ├─ 3. PLAN.md              decisiones + tareas con tier → vos aprobás
              ├─ 4. BRIEF-NN.md ──► implementador (sonnet) / senior (opus)
              │                                  │ REPORTE (≤40 líneas)
              ├─ 5. revisor (opus) ◄─────────────┘  APROBADO → [x]   RECHAZADO → reintento/escalado
              │     + auditor-seguridad si toca SQL/datos/auth/secretos
              └─ 6. verificación final → documentador (ADR + HANDOFF en Obsidian, graphify update) → cerrado
```

## Instalación

Requisitos: Claude Code reciente (probado contra la doc de septiembre 2026), **PowerShell 7** (`pwsh`) en el PATH (Windows, macOS o Linux; en Windows `winget install Microsoft.PowerShell`). Opcional: [graphify](https://github.com/safishamsi/graphify) y una carpeta de decisiones estilo Obsidian en el proyecto.

```
/plugin marketplace add royrojas/Claude-Orquesta   # este repo en GitHub
/plugin install orquesta@orquesta
```

Para probar desde una carpeta local antes de publicar:

```
/plugin marketplace add C:\ruta\a\orquesta-repo
/plugin install orquesta@orquesta
```

Reiniciá Claude Code (o `/reload-plugins`). Comprobá con `/orquesta:doctor` y mirá el enrutamiento con `/orquesta:estado`.

> Podés copiar `plugins/orquesta/skills/*` a `~/.claude/skills/` y `agents/*` a `~/.claude/agents/`, pero así **perdés las compuertas** (los hooks de plugin no se copian) y `${CLAUDE_PLUGIN_ROOT}` no se sustituye. Instalalo como plugin.

## Uso

```
claude --model fable            # o /model fable dentro de la sesión
/orquesta:arquitecto Exportar cierres de caja a CSV desde el POS
```

| Comando | Qué hace |
|---|---|
| `/orquesta:arquitecto <objetivo>` | Corre el protocolo completo. Si ya hay un PLAN `en-ejecucion` o `pausado`, **reanuda** desde donde quedó. |
| `/orquesta:revisar BRIEF-03` · `/orquesta:revisar final` | Revisión con ojos frescos bajo demanda (subagente revisor, solo lectura + build/tests). |
| `/orquesta:estado` | Modelo por trabajador y de dónde sale, estado del PLAN, graphify/Obsidian, delegaciones por modelo. |
| `/orquesta:doctor` | Diagnóstico del entorno: pwsh, hooks, config, Codex CLI y login, plugin de OpenAI, graphify, git. Corré esto después de instalar. |

El arquitecto también se activa solo si le pedís "hacelo con subagentes", "modo arquitecto", o una feature/migración de varios pasos. Para un cambio de una función no abre PLAN: lo hace directo.

## Quién hace qué

| Trabajador | Modelo por defecto | Rol |
|---|---|---|
| **arquitecto** (la sesión) | fable | Habla con vos, decide, escribe PLAN/BRIEFs, aprueba. **No escribe código.** |
| `orquesta:cartografo` | haiku | Solo lectura: graphify (`GRAPH_REPORT.md`, `graphify query`), notas de Obsidian, repo → mapa de 60 líneas. |
| `orquesta:implementador` | sonnet | Ejecuta exactamente un BRIEF. Sin alcance extra, sin commits, `BLOQUEADO` antes que adivinar. |
| `orquesta:implementador-senior` | opus | Migraciones, SQL Server + Oracle, stored procedures, concurrencia, Azure Functions, Key Vault, reintentos escalados. |
| `orquesta:revisor` | opus | Ojos frescos, solo lectura + corre build/tests. Único que marca `[x]` y la verificación final `V.`. |
| `orquesta:auditor-seguridad` | opus | Inyección, parametrización, secretos, privilegio. Precarga la skill `security-injection-audit` si la tenés. |
| `orquesta:documentador` | sonnet | ADR + HANDOFF en las carpetas de Obsidian, `graphify update .`. |

Cada trabajador puede correr en `motor: claude` (subagente) o `motor: codex` (proceso `codex exec`); ver [Codex como motor](#codex-como-motor-fable-planea-codex-ejecuta).

Escalado de ida: `implementador → implementador-senior → el arquitecto parte la tarea en briefs más finos`. Nunca se reformula una tarea rechazada para que pase: se difiere `[~]` con tu aprobación.

## Configurar los modelos

La config se resuelve por merge profundo: `config/orquesta.defaults.json` (plugin) ← `~/.claude/orquesta.json` (vos, todos los proyectos) ← `.claude/orquesta.json` (este proyecto). Solo escribís las claves que cambian:

```json
{
  "trabajadores": {
    "implementador": { "modelo": "opus" },
    "revisor":       { "modelo": "fable" }
  },
  "limites": { "max_paralelo": 2 }
}
```

Valores: `haiku`, `sonnet`, `opus`, `fable` o `inherit` (el modelo de la sesión); los IDs completos (`claude-sonnet-5`) no los acepta el Agent tool, usá el alias. El arquitecto pasa `model:` en **cada** llamada al subagente, así que tu config manda sobre el frontmatter de los agentes. Si en el chat decís "usá opus para todo", eso manda durante esa orquestación y queda anotado en `## Enrutamiento → Overrides` del PLAN.

El modelo del arquitecto es el de la sesión (`claude --model fable`); la config solo lo declara para avisarte si no coincide. Verificá con `/tasks` qué modelo corre cada subagente.

Ejemplo completo en `ejemplos/orquesta.json`. Todas las claves en `config/orquesta.defaults.json`.

## Codex como motor: Fable planea, Codex ejecuta

Los subagentes de Claude Code solo corren modelos Claude, pero un trabajador de orquesta no tiene que ser un subagente: puede ser un proceso `codex exec` (modo no interactivo de [Codex CLI](https://developers.openai.com/codex/noninteractive)). Configurá el motor por trabajador:

```json
{
  "trabajadores": {
    "implementador":        { "motor": "codex" },
    "implementador-senior": { "motor": "codex" },
    "revisor":              { "motor": "claude", "modelo": "opus" },
    "auditor-seguridad":    { "motor": "claude", "modelo": "opus" }
  },
  "motores": { "codex": { "sandbox": "workspace-write", "razonamiento": "high" } }
}
```

Con eso, Fable clarifica y escribe los BRIEFs, `scripts/Invoke-Codex.ps1` se los pasa a Codex con las **mismas instrucciones del rol** (`agents/implementador.md`), y Opus (o Fable, es una línea de config) revisa y audita en subagentes independientes con contexto limpio: revisión entre proveedores distintos. Sin `modelo` se usa `motores.codex.modelo` y, si está vacío, el default de tu `~/.codex/config.toml`. Requiere Codex CLI instalado y `codex login` hecho.

Qué hace el wrapper: aplica las mismas compuertas (sin PLAN `en-ejecucion`, sin BRIEF o con BRIEF mal formado no corre), arma el prompt en la forma que OpenAI recomienda para GPT-5.x (bloques `<role_instructions>`, `<task>`, `<default_follow_through_policy>`, `<action_safety>`, `<verification_loop>`, `<grounding_rules>` y un contrato de salida explícito), pide **salida estructurada** con `--output-schema` (`schemas/reporte.schema.json` para implementadores, `schemas/revision.schema.json` para revisor/auditor: dictamen, criterios ✓/✗ con evidencia, hallazgos con severidad, archivo:línea y confianza 0-1), guarda el JSON crudo y lo renderiza al mismo formato REPORTE/REVISIÓN que producen los trabajadores de Claude, registra tokens de Codex en la bitácora, y en los reintentos del mismo rol usa `codex exec resume <thread>` para que Codex conserve el contexto (al escalar de tier arranca limpio). También sirve para `-Rol revisor` (Codex revisando lo que implementó Claude) o `-Rol cartografo`. `"salida_estructurada": false` vuelve a texto libre.

Sandbox: `workspace-write` bloquea red; si tu `dotnet restore` necesita bajar paquetes dentro de la corrida, restaurá antes o usá `"sandbox": "danger-full-access"` (solo en tu máquina). En Windows, Codex CLI se instala con `npm i -g @openai/codex`.

### Convivencia con el plugin oficial de OpenAI

[`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) (`/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex`) es un puente hacia Codex: revisión nativa, revisión adversarial, tareas en background, transferencia de sesión. No orquesta nada, así que no compite con orquesta: se complementan. Recomendado tenerlo instalado para `/codex:review` antes de un commit y para `/codex:adversarial-review --base <rama>` como revisión de diseño de otro proveedor antes de la verificación final de un PLAN (el arquitecto lo propone en el cierre). `/orquesta:doctor` te dice si está instalado.

## Las compuertas

| Compuerta | Evento | Dispara cuando | Se destraba |
|---|---|---|---|
| Aviso de sesión | `SessionStart` | Al abrir, reanudar o compactar una sesión en un proyecto con PLAN abierto (`en-ejecucion`, `pausado`, `planificando`). | No bloquea: le recuerda a Claude el estado y las tareas abiertas, y a vos te muestra una línea. |
| Delegación | `PreToolUse(Agent)` | Se delega a `implementador*`/`documentador` (o cualquier prompt ≥ 1200 chars) sin PLAN, con PLAN en `planificando`/`cerrado`, o a un implementador cuyo BRIEF referenciado no existe o **no pasa la validación de forma** (≥ 2 criterios numerados concretos, comandos en `## Cómo verificar`, línea `NO tocar:`, sin marcadores de plantilla). Un brief inline se acepta solo con criterios numerados. | PLAN en `en-ejecucion` + BRIEF que pase `scripts/Test-Brief.ps1`. `cartografo`, `revisor`, `auditor`, `Explore`, `Plan` y `fork` nunca se gobiernan. |
| El arquitecto no edita | `PreToolUse(Edit\|Write)` | PLAN `en-ejecucion` y el hilo principal (no un subagente) escribe fuera de `.orquesta/`, `.claude/`, `docs/`, carpetas de Obsidian o `*.md`. | Delegar, o `estado: pausado` para un ajuste trivial autorizado. |
| Cierre | `Stop` | PLAN `en-ejecucion` con tareas `[ ]` al terminar el turno. **Una vez por sesión.** | Seguir, diferir `[~]`, o `estado: pausado` si esperás al usuario. |
| Bitácora | `SubagentStop` | Siempre: registra tipo, id, tamaño y estado del reporte en `.orquesta/bitacora.jsonl`. Si el reporte pasa 1.5× el límite, le pide al trabajador resumir. | — |

Apagar: `compuertas.<nombre>: false` en la config, o `ORQUESTA_GATES=0` en el entorno para toda la sesión. Los hooks corren con `pwsh -NoProfile`; si `pwsh` no está, Claude Code muestra un aviso no bloqueante y el protocolo sigue solo por instrucciones.

Estados del PLAN: `planificando` → `en-ejecucion` → `cerrado`, más `pausado` (escape). Las compuertas leen `estado:` del frontmatter y los ítems `- [ ]` bajo `## Tareas`.

## Qué deja en tu proyecto

```
.orquesta/
├── PLAN.md            # el ledger: clarificado, decisiones, enrutamiento, tareas, bitácora de revisión
├── briefs/BRIEF-NN.md # spec autocontenida por tarea
├── reportes/          # detalle largo de trabajadores/revisores
├── bitacora.jsonl     # (no versionado) spawns y stops con modelo → métricas
└── .gitignore         # excluye bitacora.jsonl y marcadores de sesión
docs/decisiones/ADR-YYYYMMDD-slug.md     # Obsidian: una decisión por nota, con frontmatter y [[wikilinks]]
docs/handoffs/HANDOFF-YYYYMMDD-slug.md   # para el compañero (o vos) que retoma
```

PLAN y briefs **sí** se versionan: son la trazabilidad. Para un plan nuevo, archivá el anterior como `PLAN-<tema>-archivo.md`.

## Integración con graphify y Obsidian

- Si existe `graphify-out/`, el cartógrafo lee `GRAPH_REPORT.md`/`wiki/index.md` y corre `graphify query` antes de tocar el código; si hay `needs_update`, te avisa. Al cerrar, el documentador corre `graphify update .` (`contexto.graphify.actualizar_al_cerrar`).
- Las notas van a `contexto.obsidian.carpeta_decisiones` y `carpeta_handoffs` (por defecto `docs/decisiones`, `docs/handoffs`) con prefijos `ADR-`/`HANDOFF-`. Si tu vault usa otra estructura, cambialo en `.claude/orquesta.json`.
- Si el proyecto no tiene grafo, `/orquesta:estado` te sugiere correr `/graphify .` (o tu propia skill de setup de proyecto) primero.

## Estructura del plugin

```
plugins/orquesta/
├── .claude-plugin/plugin.json
├── skills/
│   ├── arquitecto/        SKILL.md (protocolo) · referencias/ (enrutamiento, brief-checklist, revision-checklist) · plantillas/ (PLAN, BRIEF, REPORTE, ADR, HANDOFF)
│   ├── revisar/           SKILL.md (context: fork → orquesta:revisor)
│   ├── estado/            SKILL.md
│   └── doctor/            SKILL.md
├── agents/                cartografo · implementador · implementador-senior · revisor · auditor-seguridad · documentador
├── hooks/hooks.json       las 5 compuertas → scripts/*.ps1
├── scripts/               OrquestaCommon.ps1 · Gate-Delegacion · Gate-Edicion · Gate-Cierre · Log-Delegacion · Aviso-Sesion · Show-Estado · Doctor-Orquesta · Resolve-OrquestaConfig · Initialize-Orquesta · Test-Brief · Invoke-Codex
├── schemas/               reporte.schema.json · revision.schema.json (salida estructurada de Codex)
├── config/orquesta.defaults.json
├── ejemplos/              orquesta.json · orquesta-codex.json
└── tests/                 Test-Orquesta.ps1 · fake-codex.ps1
```

## Pruebas

```powershell
pwsh -NoProfile -File plugins/orquesta/tests/Test-Orquesta.ps1
```

181 aserciones sin dependencias: JSON de manifiestos y hooks, frontmatter de agentes y skills, sintaxis de todos los scripts, merge de config, y cada compuerta alimentada con el JSON que Claude Code manda por stdin (deny/allow/block/nudge, `agent_id`, `stop_hook_active`, `ORQUESTA_GATES`), más el motor Codex contra un `codex` falso (compuertas, flags, REPORTE, thread_id, resume, tokens), la validación de forma de BRIEFs, el aviso de sesión, la salida estructurada (JSON → REPORTE/REVISIÓN) y el doctor.

El repo trae un workflow de GitHub Actions (`.github/workflows/tests.yml`) que corre la misma suite en **windows-latest y ubuntu-latest** en cada push. Es la prueba en Windows que no se puede hacer desde Linux: rutas con `\`, shims `.cmd`, finales de línea.

## Limitaciones conocidas

- Las compuertas verifican **forma**, no fidelidad: que exista un BRIEF con criterios, no que los criterios sean buenos. Eso lo cubre el revisor.
- El enrutamiento por modelo depende de que Claude Code honre el parámetro `model` por invocación (orden documentado: invocación → frontmatter → `CLAUDE_CODE_SUBAGENT_MODEL` → sesión). Si tenés `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, todos los subagentes corren en ese modelo.
- Con fork mode (por defecto en sesiones interactivas) los subagentes corren en background y sus reportes llegan como notificaciones en turnos siguientes: el arquitecto espera antes de revisar.
- Los agentes de plugin no admiten `hooks`, `mcpServers` ni `permissionMode` en su frontmatter (restricción de Claude Code); las compuertas viven en `hooks/hooks.json`.

## Licencia

MIT.
