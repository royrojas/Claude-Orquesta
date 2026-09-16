<#
.SYNOPSIS
  Hook SubagentStop: registra el cierre de cada subagente en .orquesta/bitacora.jsonl (tipo, id, tamaño del reporte)
  y, si el reporte final supera limites.max_lineas_reporte, le pide al trabajador que lo resuma
  y deje el detalle en .orquesta/reportes/. Respeta stop_hook_active.

  El campo `estado` se infiere buscando BLOQUEADO/RECHAZADO/PARCIAL/APROBADO/COMPLETADO en el
  reporte (formato REPORTE/REVISIÓN). El `documentador` no usa ese vocabulario (su reporte no
  tiene un campo de estado, ver agents/documentador.md) — que le quede vacío es esperado, no un
  error. No usar `estado` como fuente única de métricas: es una heurística de texto, no un
  campo estructurado.
#>
. "$PSScriptRoot/OrquestaCommon.ps1"

$in = Read-HookInput
if ($null -eq $in) { exit 0 }

$cwd = Get-Prop $in 'cwd'; if (-not $cwd) { $cwd = (Get-Location).Path }
$cfg = Get-OrquestaConfig -Cwd $cwd

$tipo   = "$(Get-Prop $in 'agent_type')"
$short  = ($tipo -replace '^.*:', '').ToLowerInvariant()
$msg    = "$(Get-Prop $in 'last_assistant_message')"
$lineas = if ($msg) { @($msg -split "`r?`n").Count } else { 0 }

Add-BitacoraEntry -Cwd $cwd -Config $cfg -Entry @{
    evento = 'stop'; sesion = "$(Get-Prop $in 'session_id')"; agente = $short
    agent_id = "$(Get-Prop $in 'agent_id')"; lineas_reporte = $lineas; chars_reporte = $msg.Length
    estado = $(if ($msg -match '(?i)\bBLOQUEADO\b') { 'BLOQUEADO' } elseif ($msg -match '(?i)\bRECHAZADO\b') { 'RECHAZADO' } elseif ($msg -match '(?i)\bPARCIAL\b') { 'PARCIAL' } elseif ($msg -match '(?i)\bAPROBADO\b') { 'APROBADO' } elseif ($msg -match '(?i)\bCOMPLETADO\b') { 'COMPLETADO' } else { '' })
}

if ((Get-Prop $in 'stop_hook_active') -eq $true) { exit 0 }
if (-not (Test-OrquestaGatesEnabled)) { exit 0 }

$max = [int](Get-Prop $cfg 'limites.max_lineas_reporte')
$trabajadores = @('implementador', 'implementador-senior', 'revisor', 'auditor-seguridad', 'documentador', 'cartografo')
if ($short -in $trabajadores -and $max -gt 0 -and $lineas -gt ($max * 1.5)) {
    Add-ToolContext -Event 'SubagentStop' -Context ("orquesta: tu reporte tiene $lineas líneas; el límite es $max. " +
        "Guardá el detalle completo en $(Get-Prop $cfg 'rutas.reportes')/ y respondé solo con el resumen en formato REPORTE (estado, cambios, criterios ✓/✗ con evidencia, pruebas, dudas).")
}
exit 0
