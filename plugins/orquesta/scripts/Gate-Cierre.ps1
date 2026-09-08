<#
.SYNOPSIS
  Compuerta Stop: si el PLAN está `en-ejecucion` y quedan tareas abiertas, bloquea el fin del turno UNA vez por sesión
  y le recuerda al arquitecto sus tres salidas: seguir, diferir con aprobación ([~]) o pausar (`estado: pausado`) si espera al usuario.
  Respeta stop_hook_active para no entrar en bucle.
#>
. "$PSScriptRoot/OrquestaCommon.ps1"

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
if (Get-Prop $in 'agent_id') { exit 0 }
if ((Get-Prop $in 'stop_hook_active') -eq $true) { exit 0 }
if (-not (Test-OrquestaGatesEnabled)) { exit 0 }

$cwd = Get-Prop $in 'cwd'; if (-not $cwd) { $cwd = (Get-Location).Path }
$cfg = Get-OrquestaConfig -Cwd $cwd
if (-not (Get-Prop $cfg 'compuertas.cierre')) { exit 0 }

$plan = Get-PlanInfo -Cwd $cwd -Config $cfg
if (-not $plan.Existe -or $plan.Estado -ne 'en-ejecucion' -or $plan.Abiertos -eq 0) { exit 0 }

# Una sola vez por sesión: marcador en .orquesta/
$sesion = "$(Get-Prop $in 'session_id')"; if (-not $sesion) { $sesion = 'sin-sesion' }
$raiz = Join-Path $cwd (Get-Prop $cfg 'rutas.raiz')
$marker = Join-Path $raiz ".cierre-$sesion"
if (Test-Path -LiteralPath $marker) { exit 0 }
try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }

$lista = (@($plan.ItemsAbiertos | Select-Object -First 5) -join ' | ')
Write-HookJson @{
    decision = 'block'
    reason   = ("orquesta: el PLAN sigue 'en-ejecucion' con $($plan.Abiertos) tarea(s) abierta(s): $lista. " +
                "Antes de cerrar el turno elegí una: (a) seguí delegando y revisando; (b) diferí ítems con aprobación explícita del usuario marcándolos '- [~]'; " +
                "(c) si estás esperando una decisión del usuario, cambiá 'estado: pausado' y decíselo en una línea. " +
                "Si todo terminó, corré la verificación final con orquesta:revisor, marcá 'V.' y poné 'estado: cerrado'. (Esta compuerta dispara una vez por sesión.)")
}
exit 0
