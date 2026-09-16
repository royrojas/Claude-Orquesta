<#
.SYNOPSIS
  Registra el resultado de una tarea del PLAN en una sola llamada: marca `- [x]` (APROBADO) o `- [~]` (DIFERIDO) en
  ## Tareas, agrega la fila a ## Bitácora de revisión y deja el evento en .orquesta/bitacora.jsonl.
  Reemplaza los 2-3 Edits que el arquitecto hacía por dictamen: cada Edit es un request que relee todo su contexto.
.EXAMPLE
  pwsh -NoProfile -File scripts/Marcar-Tarea.ps1 -Tarea 3 -Resultado APROBADO -Trabajador "implementador (sonnet)" -Intento 2 -Revisor "revisor (opus)" -Notas "ratificado: NULL en campos mal tipados"
  pwsh -NoProfile -File scripts/Marcar-Tarea.ps1 -Tarea 4 -Resultado RECHAZADO -Trabajador "implementador (codex gpt-5.6-sol)" -Intento 1 -Revisor "auditor (opus)" -Notas "[Debe] XSS en recHtml"
  pwsh -NoProfile -File scripts/Marcar-Tarea.ps1 -Tarea V. -Resultado APROBADO -Revisor "revisor (opus)"
#>
param(
    [string]$Cwd = (Get-Location).Path,
    [Parameter(Mandatory)][string]$Tarea,
    [Parameter(Mandatory)][ValidateSet('APROBADO', 'RECHAZADO', 'DIFERIDO', 'COMPLETADO', 'PARCIAL', 'BLOQUEADO', 'INFRA', 'REABIERTA')][string]$Resultado,
    [string]$Trabajador = '',
    [string]$Intento = '',
    [string]$Revisor = '',
    [string]$Notas = ''
)
. "$PSScriptRoot/OrquestaCommon.ps1"

$cfg  = Get-OrquestaConfig -Cwd $Cwd
$plan = Get-PlanInfo -Cwd $Cwd -Config $cfg
if (-not $plan.Existe) { Write-Output "orquesta: no hay PLAN en ``$($plan.Ruta)``. Creá uno con Initialize-Orquesta.ps1."; exit 1 }

$utf8 = [Text.UTF8Encoding]::new($false)
$raw = [IO.File]::ReadAllText($plan.Ruta, $utf8)
$nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
$lines = [Collections.Generic.List[string]]@($raw -split "`r?`n")

# ---- 1. Marca en ## Tareas
$idTarea = [regex]::Escape($Tarea.TrimEnd('.'))
$marca = switch ($Resultado) { 'APROBADO' { 'x' } 'DIFERIDO' { '~' } 'REABIERTA' { ' ' } default { $null } }
$enTareas = $false; $idx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '^\s*##\s+') { $enTareas = ($l -match '^\s*##\s+Tareas'); continue }
    if ($enTareas -and $l -match "^\s*-\s*\[( |x|X|~)\]\s*$idTarea\.?\s") { $idx = $i; break }
}
if ($idx -lt 0) { Write-Output "orquesta: no encontré la tarea ``$Tarea`` en ## Tareas de ``$($plan.Ruta)``."; exit 1 }
$marcaTxt = 'sin cambio de marca'
if ($null -ne $marca) {
    $lines[$idx] = [regex]::Replace($lines[$idx], '^(\s*-\s*\[)( |x|X|~)(\])', ('${1}' + $marca + '${3}'))
    $marcaTxt = "-> [$marca]"
}

# ---- 2. Fila en ## Bitácora de revisión (después de la última fila de la tabla; si no hay sección, se crea al final)
function Limpiar([string]$s) { return (($s -replace '\|', '/') -replace '\r?\n', ' ').Trim() }
$fila = "| $Tarea | $(Limpiar $Trabajador) | $(Limpiar $Intento) | $(Limpiar $Revisor) | $Resultado | $(Limpiar $Notas) |"
$encabezado = '| # | Trabajador (modelo) | Intento | Revisor | Resultado | Notas |'
$separador  = '|---|---|---|---|---|---|'
$ini = -1; $fin = $lines.Count
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($ini -lt 0) { if ($lines[$i] -match '^\s*##\s+Bit[aá]cora de revisi') { $ini = $i }; continue }
    if ($lines[$i] -match '^\s*##\s+') { $fin = $i; break }
}
if ($ini -lt 0) {
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) { $lines.RemoveAt($lines.Count - 1) }
    $lines.Add(''); $lines.Add('## Bitácora de revisión'); $lines.Add($encabezado); $lines.Add($separador); $lines.Add($fila); $lines.Add('')
} else {
    $ultima = -1
    for ($i = $ini + 1; $i -lt $fin; $i++) { if ($lines[$i] -match '^\s*\|') { $ultima = $i } }
    if ($ultima -lt 0) { $lines.Insert($ini + 1, $encabezado); $lines.Insert($ini + 2, $separador); $ultima = $ini + 2 }
    $lines.Insert($ultima + 1, $fila)
}
[IO.File]::WriteAllText($plan.Ruta, ($lines -join $nl), $utf8)

# ---- 3. Evento estructurado en la bitácora JSONL
Add-BitacoraEntry -Cwd $Cwd -Config $cfg -Entry @{
    evento = 'tarea'; tarea = $Tarea; resultado = $Resultado; trabajador = $Trabajador; intento = "$Intento"; revisor = $Revisor; notas = $Notas
}

$rel = Get-RelativePathSafe -Path $plan.Ruta -Base $Cwd
Write-Output "orquesta: tarea $Tarea $Resultado $marcaTxt · fila agregada a la bitácora de revisión de ``$rel``."
