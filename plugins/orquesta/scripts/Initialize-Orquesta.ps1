<#
.SYNOPSIS
  Crea la carpeta .orquesta/ del proyecto con el PLAN.md (desde plantilla), briefs/, reportes/ y un .gitignore local.
  El PLAN arranca en `estado: planificando`; el arquitecto lo completa (Clarificado, Decisiones, Tareas) y, aprobado
  por el usuario, lo pasa a `en-ejecucion`.
.EXAMPLE
  pwsh -NoProfile -File scripts/Initialize-Orquesta.ps1 -Objetivo "Exportación CSV de cierres de caja"
  pwsh -NoProfile -File scripts/Initialize-Orquesta.ps1 -Objetivo "..." -Force   # reemplaza un PLAN existente
#>
param(
    [Parameter(Mandatory)][string]$Objetivo,
    [string]$Cwd = (Get-Location).Path,
    [string]$Arquitecto,
    [switch]$Force
)
. "$PSScriptRoot/OrquestaCommon.ps1"

$cfg   = Get-OrquestaConfig -Cwd $Cwd
$root  = Get-OrquestaPluginRoot
$raiz  = Join-Path $Cwd (Get-Prop $cfg 'rutas.raiz')
$plan  = Join-Path $Cwd (Get-Prop $cfg 'rutas.plan')
$briefs   = Join-Path $Cwd (Get-Prop $cfg 'rutas.briefs')
$reportes = Join-Path $Cwd (Get-Prop $cfg 'rutas.reportes')

if ((Test-Path -LiteralPath $plan) -and -not $Force) {
    $info = Get-PlanInfo -Cwd $Cwd -Config $cfg
    Write-Output "orquesta: ya existe $plan (estado: $($info.Estado), objetivo: $($info.Objetivo)). Usá -Force para reemplazarlo o archivalo primero (PLAN-<tema>-archivo.md)."
    exit 1
}

foreach ($d in @($raiz, $briefs, $reportes)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

# .gitignore local: la bitácora y los marcadores de sesión no se versionan; PLAN y briefs sí.
$gi = Join-Path $raiz '.gitignore'
if (-not (Test-Path -LiteralPath $gi)) {
    Set-Content -LiteralPath $gi -Value "bitacora.jsonl`n.cierre-*`n" -Encoding UTF8
}

if (-not $Arquitecto) { $Arquitecto = "$(Get-Prop $cfg 'orquestador.modelo')" }
$rama = ''
try { $rama = (& git -C $Cwd rev-parse --abbrev-ref HEAD 2>$null); if ($LASTEXITCODE -ne 0) { $rama = '' } } catch { $rama = '' }
if (-not $rama) { $rama = '(sin git)' }

# Tabla de enrutamiento desde la config efectiva
$tabla = New-Object System.Collections.Generic.List[string]
$tabla.Add('| Trabajador | Motor | Modelo | Cuándo |')
$tabla.Add('|---|---|---|---|')
foreach ($p in $cfg.trabajadores.PSObject.Properties) {
    if ($p.Name -like '_*') { continue }
    $motor = "$(Get-Prop $p.Value 'motor')"; if (-not $motor) { $motor = 'claude' }
    $tabla.Add("| orquesta:$($p.Name) | $motor | $($p.Value.modelo) | $($p.Value.rol) |")
}

$tpl = Get-Content -LiteralPath (Join-Path $root 'skills/arquitecto/plantillas/PLAN.md') -Raw -Encoding UTF8
$contenido = $tpl.
    Replace('{{OBJETIVO}}', $Objetivo).
    Replace('{{FECHA}}', (Get-Date).ToString('yyyy-MM-dd')).
    Replace('{{ARQUITECTO}}', $Arquitecto).
    Replace('{{RAMA}}', $rama).
    Replace('{{TABLA_ENRUTAMIENTO}}', ($tabla -join "`n"))

Set-Content -LiteralPath $plan -Value $contenido -Encoding UTF8

Write-Output "orquesta: PLAN creado en $plan (estado: planificando)."
Write-Output "Siguiente: completá ## Clarificado, ## Decisiones y ## Tareas; presentá el plan; con el OK del usuario cambiá a 'estado: en-ejecucion'."
Write-Output "Briefs en $briefs · Reportes en $reportes · Plantillas en $(Join-Path $root 'skills/arquitecto/plantillas')"
