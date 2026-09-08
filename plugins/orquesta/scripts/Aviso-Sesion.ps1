<#
.SYNOPSIS
  Hook SessionStart: si el proyecto tiene un PLAN de orquesta abierto (en-ejecucion, pausado o planificando),
  se lo recuerda a Claude (additionalContext) y al usuario (systemMessage) al abrir, reanudar o compactar la sesión.
#>
. "$PSScriptRoot/OrquestaCommon.ps1"

$in = Read-HookInput
$cwd = if ($in) { Get-Prop $in 'cwd' } else { $null }
if (-not $cwd) { $cwd = (Get-Location).Path }

$cfg  = Get-OrquestaConfig -Cwd $cwd
$plan = Get-PlanInfo -Cwd $cwd -Config $cfg
if (-not $plan.Existe -or $plan.Estado -in @('cerrado', $null, '')) { exit 0 }

$abiertas = @($plan.ItemsAbiertos | Select-Object -First 4 | ForEach-Object { ($_ -split ' — ')[0] })
$detalle = switch ($plan.Estado) {
    'en-ejecucion' { "Tiene $($plan.Abiertos) tarea(s) abierta(s): $($abiertas -join ' | '). El skill /orquesta:arquitecto reanuda desde el PLAN y los briefs sin volver a clarificar." }
    'pausado'      { "Está pausado (esperando al usuario o un ajuste trivial); $($plan.Abiertos) tarea(s) abierta(s). Al retomar, /orquesta:arquitecto lo vuelve a 'en-ejecucion'." }
    'planificando' { "Está en planificación: el PLAN aún no fue aprobado por el usuario. Sin aprobación no se delega implementación." }
    default        { "Estado: $($plan.Estado)." }
}
$ctx = "orquesta: este proyecto tiene un PLAN de orquestación en '$(Get-Prop $cfg 'rutas.plan')' con objetivo '$($plan.Objetivo)' y estado '$($plan.Estado)'. $detalle La config efectiva se ve con /orquesta:estado."
Write-HookJson @{
    systemMessage      = "orquesta: PLAN '$($plan.Objetivo)' en estado $($plan.Estado) ($($plan.Abiertos) abiertas). /orquesta:arquitecto para reanudar."
    hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $ctx }
}
exit 0
