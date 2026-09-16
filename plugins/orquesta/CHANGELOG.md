# Changelog

## 1.3.7 — 2026-09-16
- `init` ya no corre `Show-Estado.ps1` al cerrar: lanzar `pwsh` desde el skill dispara el
  prompt de Claude Code "nested PowerShell process which cannot be validated" (regla de
  seguridad para shells anidados, no la salva `allowed-tools`). Ahora cierra apuntando a
  `/orquesta:doctor` y `/orquesta:estado`, que corren vía el `!` del skill sin pedir permiso —
  y es coherente con el orden fijo init → doctor.
- README §16: dos filas nuevas — el prompt de shell anidado (qué es, elegir "don't ask again"
  una vez por script) y por qué la ruta del prompt es la del repo `claude-orquesta` con un
  marketplace local (`source: directory` → `${CLAUDE_PLUGIN_ROOT}` es la carpeta fuente).
- 1 aserción nueva (213).

## 1.3.6 — 2026-09-16
- `doctor` y `estado` leen la línea `- Decisiones:` del `CLAUDE.md` del proyecto **solo para
  diagnosticar** (`Get-ObsidianDesajusteClaudeMd`, mismo parser conservador del init): si
  declara una carpeta absoluta distinta de la que resuelve la config, doctor lo marca con ✗ y
  "Siguientes pasos: corré /orquesta:init", y estado lo agrega a la línea de Obsidian (lo lee el
  arquitecto al arrancar). La config sigue mandando; esto no cambia ninguna ruta. Encontrado en
  AI Monitor: la config resolvía al default del repo y el CLAUDE.md apuntaba al vault, y el
  script solo decía "aún no existe".
- `init`: al agregar las carpetas de Obsidian a una config existente, escribe la ruta
  **absoluta tal cual** figura en el CLAUDE.md. En AI Monitor el skill la había convertido a
  `Proyectos/AI.Monitor/Decisiones` (la forma relativa a `vault_root`), que sin `vault_root`
  se resuelve contra el repo y queda apuntando a una carpeta inexistente — y en un segundo
  intento el skill "arregló" la inconsistencia creando `~/.claude/orquesta.json` con
  `vault_root` por su cuenta, el archivo global que el usuario había decidido no tener. Ahora
  init tiene prohibido crear o editar el archivo global: solo toca el `.claude/orquesta.json`
  del proyecto. README §13 reordenado: la ruta absoluta es el default simple; `vault_root` es
  la opción para equipos, y la pide el usuario, no el skill.
- Orden fijo documentado en todo el manual y en el propio skill de init: **`/orquesta:init` →
  `/orquesta:doctor` → `/orquesta:arquitecto`**. init es idempotente y doctor solo lectura, así
  que init primero nunca hace daño; al revés, doctor reporta una config que init está por cambiar.
- 4 aserciones nuevas (212).

## 1.3.5 — 2026-09-16
- **`/orquesta:init`** (`Initialize-OrquestaConfig.ps1`): crea `.claude/orquesta.json` en el
  proyecto si no existe — un esqueleto mínimo y editable con un `_doc` por bloque
  (`trabajadores`, `motores.codex`, `contexto.obsidian`). No vuelca los defaults: vacío de
  overrides se comporta igual que los defaults y sigue al día cuando el plugin cambia. Nunca
  sobreescribe uno existente. Después, el skill pregunta con `AskUserQuestion` (una ronda)
  quién implementa, quién toma las tareas difíciles y quién revisa/audita — y el razonamiento
  de Codex si eligió Codex — y escribe **solo** las claves elegidas sobre el esqueleto (si eligió
  el default, no escribe la clave). Avisa si implementador y revisor quedaron en el mismo modelo
  del mismo proveedor. Termina mostrando `Show-Estado` con la fuente de cada valor.
- Pre-llena `carpeta_decisiones`/`carpeta_handoffs` leyendo la línea `- Decisiones: <ruta>` de
  la sección "Memoria del proyecto (Obsidian)" del `CLAUDE.md` del proyecto (la que deja el skill
  `configurar-proyecto`) — solo si es una ruta absoluta y no está abreviada con `...`; si no,
  no inventa nada y quedan los defaults. Se lee una vez al crear, no en cada corrida.
- `doctor` sugiere `/orquesta:init` cuando el proyecto no tiene `.claude/orquesta.json`; sigue
  siendo solo lectura (no crea nada).
- Decisión de diseño registrada: la config es **por proyecto**; el `~/.claude/orquesta.json`
  global es opcional y no hace falta crearlo. El merge por clave se mantiene (sin global, ambos
  modelos son idénticos).
- El init pregunta también dónde van las notas de cierre (dentro del repo — default, sin
  Obsidian —, en una carpeta del vault, o ninguna → `contexto.obsidian.usar: false`), solo
  cuando el CLAUDE.md no las pre-llenó. Funciona sin Obsidian, sin graphify y sin
  `configurar-proyecto`: todo eso es opcional (aserción explícita del caso sin CLAUDE.md).
- 17 aserciones nuevas (208).

## 1.3.4 — 2026-09-16
- **Rutas absolutas de Obsidian, arregladas de raíz.** `Join-Path` no soportaba un hijo
  absoluto (`Show-Estado.ps1`/`Doctor-Orquesta.ps1` armaban una ruta inválida y decían "no
  existe" aunque la carpeta estuviera ahí). Nuevo `Resolve-ObsidianPath` compartido en
  `OrquestaCommon.ps1`, usado también por `Gate-Edicion.ps1`.
- **`contexto.obsidian.vault_root`** (nuevo, personal — va en `~/.claude/orquesta.json`, nunca
  en el del proyecto): si está seteado, `carpeta_decisiones`/`carpeta_handoffs` (cuando no son
  ya absolutas) se resuelven contra el vault en vez de contra el repo. El `.claude/orquesta.json`
  del proyecto puede declarar algo compartible como `"Proyectos/MiProyecto/Decisiones"` sin
  exponer la ruta en disco de nadie; cada persona del equipo lo resuelve contra su propio vault.
- **`contexto.obsidian.usar` ya tiene efecto** (antes existía en la config pero ningún script lo
  leía): `false` apaga ADR/HANDOFF por completo — el arquitecto no delega al documentador,
  `/orquesta:estado`/`/orquesta:doctor` muestran "desactivado".
- Encontrado en un proyecto real (AI Monitor) al probar la orquestación completa: la config no
  sobreescribía `carpeta_decisiones`, así que usaba el default (`docs/decisiones`, dentro del
  repo) mientras las notas reales vivían en el vault — exactamente el caso que resuelve
  `vault_root`.
- 6 aserciones nuevas (191).

## 1.3.3 — 2026-09-16
- Arquitecto: al cerrar el PLAN, ahora le pasa al `documentador` las rutas **resueltas y
  literales** de `contexto.obsidian.carpeta_decisiones`/`carpeta_handoffs` en vez de "las
  carpetas de la config" en abstracto — encontrado en una orquestación real de punta a punta
  donde el documentador, sin esa ruta explícita, improvisó `.orquesta/decisiones` en vez de
  `docs/decisiones`.
- `Log-Delegacion.ps1`: la detección de `estado` en la bitácora no reconocía `PARCIAL` (solo
  BLOQUEADO/RECHAZADO/APROBADO/COMPLETADO) — agregado. Documentado que el `documentador` no
  tiene ese campo por diseño (su reporte no es un REPORTE/REVISIÓN), así que su `estado` vacío
  es esperado, no un bug.
- Validado en esta versión: una orquestación completa real de punta a punta (cartógrafo →
  clarificación → PLAN → BRIEF → implementador → revisor → verificación final → documentador)
  con subagentes de Claude reales y tests corridos de forma independiente (10/10 OK), y motor
  codex contra Codex CLI real hasta `COMPLETADO` (ver README §16 y el vault del proyecto).
- 185 aserciones.

## 1.3.2 — 2026-09-16
- Overrides de modelo por chat: si la frase suena a preferencia permanente ("de ahora en más", "siempre en este proyecto") en vez de puntual, el arquitecto pregunta si la persiste en `.claude/orquesta.json` o `~/.claude/orquesta.json` (merge de solo las claves que cambian, nunca reescribe el archivo entero); sin confirmación explícita queda como override de esa orquestación nada más, como antes.
- Manual: nueva sección "Ejemplo rápido" al inicio del README (antes del índice) con un JSON real de enrutamiento mixto Claude+Codex. §7/§8: catálogo real de modelos de Codex (`gpt-6-astra`, `gpt-reserve`, `gpt-5.6-sol/terra/luna`, `gpt-5.5`) con para qué sirve cada uno, y la salvedad de que `motores.codex.razonamiento` es una sola clave global (no por trabajador), a diferencia de `modelo` que sí es por rol.
- 182 aserciones.

## 1.3.1 — 2026-09-15
- Config: un trabajador agregado en `.claude/orquesta.json` sin `esfuerzo`/`rol` ya no tumba `Show-Estado` ni `Initialize-Orquesta` (StrictMode). `Get-TrabajadorInfo` compartido: la tabla del PLAN muestra el modelo efectivo también para codex.
- Arquitecto: regla explícita para `model:` — solo alias del Agent tool; `inherit` → sin `model:`; ID completo → el alias que contiene + aviso. Reintentos con motor codex documentados en el skill y en el checklist de revisión (`-Intento N+1 -Hallazgos`, no `SendMessage`). Preferir la tool PowerShell para los `pwsh`.
- Codex: `resume` solo si el intento anterior fue del mismo rol (al escalar de tier arranca limpio); los flags que `exec resume` acepta van después del subcomando (`--sandbox`/`-C` no lo son); si `resume` no reescribe el archivo `-o`, el reporte sale del JSONL en vez de reusar el del intento anterior.
- Seguridad: `doctor` y `estado` avisan cuando el `.claude/orquesta.json` del proyecto redefine `motores.codex.comando`, `args_extra` o `sandbox = danger-full-access` (ese archivo viaja con el repo).
- UTF-8 forzado en la consola para hooks, scripts y la suite: acentos intactos desde Claude Code en Windows y sin fallos falsos al correr los tests desde Git Bash.
- `allowed-tools` de los skills separado por comas; `doctor` tolera una config inválida sin errores en cadena; `revisar` conoce `REPORTE-NN-codex.md`.
- 181 aserciones.

## 1.3.0 — 2026-09-08
- Motor Codex: prompt en bloques XML según la guía de prompting de OpenAI para GPT-5.x (task, follow-through, action_safety, verification_loop, grounding, contrato de salida).
- Salida estructurada de Codex con `--output-schema` (`schemas/reporte.schema.json`, `schemas/revision.schema.json`): estado/dictamen, criterios con evidencia, hallazgos con severidad y confianza; JSON guardado y renderizado al formato REPORTE/REVISIÓN. `motores.codex.salida_estructurada` para apagarlo.
- `/orquesta:doctor` (`Doctor-Orquesta.ps1`): diagnóstico de pwsh, hooks, config, Codex CLI y login, plugin oficial de OpenAI, graphify, Obsidian, git.
- Cierre del PLAN: paso opcional `/codex:adversarial-review` si el plugin de OpenAI está instalado.
- 166 aserciones.

## 1.2.0 — 2026-09-08
- Compuerta de delegación valida la forma del BRIEF referenciado (criterios numerados, comandos de verificación, `NO tocar`, sin marcadores); `scripts/Test-Brief.ps1` para comprobarlo antes de delegar. El wrapper de Codex aplica la misma regla.
- Hook `SessionStart` (`Aviso-Sesion.ps1`): recuerda el PLAN abierto y sus tareas al abrir, reanudar o compactar la sesión.
- CI en GitHub Actions: suite completa en windows-latest y ubuntu-latest; `.gitattributes` con LF.
- 150 aserciones.

## 1.1.0 — 2026-09-08
- Motor `codex`: cualquier trabajador puede correr en OpenAI Codex CLI (`codex exec`) con las mismas instrucciones de rol, compuertas, REPORTE y bitácora; reintentos con `resume`.
- `Show-Estado` e `Initialize-Orquesta` muestran el motor por trabajador y la disponibilidad de `codex`.
- 18 aserciones nuevas con un `codex` falso.

## 1.0.0 — 2026-09-08
- Protocolo arquitecto en 5 fases (`/orquesta:arquitecto`), revisión bajo demanda (`/orquesta:revisar`), estado (`/orquesta:estado`).
- Seis subagentes con modelo configurable por tier: cartografo, implementador, implementador-senior, revisor, auditor-seguridad, documentador.
- Cuatro compuertas en PowerShell 7: delegación, arquitecto-no-edita, cierre, bitácora.
- Config con merge defaults ← usuario ← proyecto; plantillas PLAN/BRIEF/REPORTE/ADR/HANDOFF; integración graphify + Obsidian.
- Suite de pruebas sin dependencias (117 aserciones).
