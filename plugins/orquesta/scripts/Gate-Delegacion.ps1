<#
.SYNOPSIS
  Compuerta PreToolUse(Agent): no se delega implementación sin PLAN aprobado ni sin BRIEF con criterios de aceptación.
  Además registra cada spawn en la bitácora (agente + modelo) para tener métricas de uso por modelo.

  Reglas (solo en el hilo principal; los spawns anidados dentro de subagentes no se tocan):
    - Exentos siempre: cartografo, revisor, auditor-seguridad, Explore, Plan, fork, general-purpose (salvo prompt largo).
    - Escritores (implementador, implementador-senior, documentador) o cualquier prompt >= compuerta_delegacion_chars:
        * sin PLAN                      -> deny
        * PLAN en 'planificando'        -> deny (falta aprobación del usuario)
        * PLAN en 'cerrado'             -> deny (trabajo nuevo = plan nuevo)
        * PLAN en 'pausado'             -> allow (el usuario autorizó saltarse el protocolo)
        * implementador/senior sin referencia a BRIEF ni "criterios de aceptación" -> deny
#>
. "$PSScriptRoot/OrquestaCommon.ps1"

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
if (Get-Prop $in 'agent_id') { exit 0 }                       # spawn anidado dentro de un subagente: no se gobierna aquí
if ("$(Get-Prop $in 'tool_name')" -ne 'Agent') { exit 0 }

$cwd = Get-Prop $in 'cwd'; if (-not $cwd) { $cwd = (Get-Location).Path }
$cfg = Get-OrquestaConfig -Cwd $cwd

$type   = "$(Get-Prop $in 'tool_input.subagent_type')".ToLowerInvariant()
$short  = ($type -replace '^.*:', '')
$prompt = "$(Get-Prop $in 'tool_input.prompt')"
$modelo = "$(Get-Prop $in 'tool_input.model')"

# Bitácora de spawns (aunque las compuertas estén apagadas, la métrica sirve)
Add-BitacoraEntry -Cwd $cwd -Config $cfg -Entry @{
    evento = 'spawn'; sesion = "$(Get-Prop $in 'session_id')"; agente = $(if ($short) { $short } else { 'general-purpose' })
    modelo = $(if ($modelo) { $modelo } else { 'default' }); chars_prompt = $prompt.Length
    descripcion = "$(Get-Prop $in 'tool_input.description')"
}

if (-not (Test-OrquestaGatesEnabled)) { exit 0 }
if (-not (Get-Prop $cfg 'compuertas.delegacion')) { exit 0 }

$exentos    = @('cartografo', 'revisor', 'auditor-seguridad', 'explore', 'plan', 'fork', 'claude-code-guide', 'statusline-setup')
$escritores = @('implementador', 'implementador-senior', 'documentador')
if ($short -in $exentos) { exit 0 }

$umbral = [int](Get-Prop $cfg 'limites.compuerta_delegacion_chars')
$requierePlan = ($short -in $escritores) -or ($prompt.Length -ge $umbral)
if (-not $requierePlan) { exit 0 }

$plan = Get-PlanInfo -Cwd $cwd -Config $cfg
$planRel = Get-Prop $cfg 'rutas.plan'

if (-not $plan.Existe) {
    Deny-ToolUse ("orquesta: no existe $planRel. Protocolo: (1) cartógrafo, (2) clarificar con el usuario en UNA ronda, " +
        "(3) crear el PLAN con pwsh -NoProfile -File <plugin>/scripts/Initialize-Orquesta.ps1 -Objetivo '...', " +
        "(4) presentarlo y, aprobado, poner 'estado: en-ejecucion', (5) un BRIEF por tarea en $(Get-Prop $cfg 'rutas.briefs'). Luego volvé a delegar.")
}
switch ($plan.Estado) {
    'planificando' { Deny-ToolUse "orquesta: el PLAN está en 'estado: planificando'. Presentá el plan al usuario; cuando lo apruebe, cambiá a 'estado: en-ejecucion' en $planRel y volvé a delegar." }
    'cerrado'      { Deny-ToolUse "orquesta: el PLAN actual está 'cerrado'. Si es trabajo nuevo, archivalo (renombrar a PLAN-<tema>-archivo.md) e iniciá uno nuevo con Initialize-Orquesta.ps1 -Force." }
    'pausado'      { exit 0 }
}

if ($short -in @('implementador', 'implementador-senior')) {
    $refs = @([regex]::Matches($prompt, '(?i)BRIEF-(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($refs.Count -eq 0) {
        # Sin archivo BRIEF: se acepta un brief inline solo si trae criterios de aceptación numerados.
        $numerados = ([regex]::Matches($prompt, '(?m)^\s*\d+\.\s+\S')).Count
        if ($prompt -notmatch '(?i)criterios? de aceptaci' -or $numerados -lt 2) {
            Deny-ToolUse ("orquesta: la delegación a orquesta:$short no referencia un BRIEF (BRIEF-NN) ni trae criterios de aceptación numerados. " +
                "Escribí $(Get-Prop $cfg 'rutas.briefs')/BRIEF-NN.md con la plantilla, validalo con scripts/Test-Brief.ps1 y pasale la ruta al trabajador. " +
                "Sin criterios verificables el revisor no puede aprobar nada.")
        }
    } else {
        $briefsDir = Join-Path $cwd (Get-Prop $cfg 'rutas.briefs')
        foreach ($nn in $refs) {
            $ruta = Join-Path $briefsDir "BRIEF-$nn.md"
            $forma = Test-BriefShape -Path $ruta
            if (-not $forma.Valido) {
                Deny-ToolUse ("orquesta: BRIEF-$nn no pasa la validación de forma: " + ($forma.Problemas -join ' · ') + ". " +
                    "Corregilo (plantilla en skills/arquitecto/plantillas/BRIEF.md, checklist en referencias/brief-checklist.md), " +
                    "comprobá con scripts/Test-Brief.ps1 -Brief $(Get-Prop $cfg 'rutas.briefs')/BRIEF-$nn.md y volvé a delegar.")
            }
        }
    }
}

exit 0
