<#
.SYNOPSIS
  Valida la forma de un BRIEF antes de delegar (la compuerta de delegación aplica las mismas reglas).
  Exit 0 si pasa, 2 si no.
.EXAMPLE
  pwsh -NoProfile -File scripts/Test-Brief.ps1 -Brief .orquesta/briefs/BRIEF-01.md
#>
param(
    [Parameter(Mandatory)][string]$Brief,
    [string]$Cwd = (Get-Location).Path
)
. "$PSScriptRoot/OrquestaCommon.ps1"

$path = if ([IO.Path]::IsPathRooted($Brief)) { $Brief } else { Join-Path $Cwd $Brief }
$r = Test-BriefShape -Path $path
Write-Output "BRIEF: $Brief"
Write-Output "  criterios numerados concretos: $($r.Criterios) $(if ($r.Criterios -ge 2) {'✓'} else {'✗ (mínimo 2)'})"
Write-Output "  comandos en 'Cómo verificar': $($r.Comandos) $(if ($r.Comandos -ge 1) {'✓'} else {'✗ (mínimo 1)'})"
Write-Output "  línea 'NO tocar':              $(if ($r.Problemas -match 'NO tocar') {'✗'} else {'✓'})"
Write-Output "  sin marcadores de plantilla:   $(if ($r.Problemas -match 'marcadores') {'✗'} else {'✓'})"
if ($r.Valido) { Write-Output "Resultado: VÁLIDO — se puede delegar."; exit 0 }
Write-Output "Resultado: INVÁLIDO"
foreach ($p in $r.Problemas) { Write-Output "  - $p" }
Write-Output "Referencia: skills/arquitecto/referencias/brief-checklist.md"
exit 2
