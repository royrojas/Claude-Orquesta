<#
.SYNOPSIS
  Imprime la configuración efectiva de orquesta (defaults <- usuario <- proyecto) como JSON.
.EXAMPLE
  pwsh -NoProfile -File scripts/Resolve-OrquestaConfig.ps1
  pwsh -NoProfile -File scripts/Resolve-OrquestaConfig.ps1 -Cwd C:\repos\MiProyecto -Pretty
#>
param(
    [string]$Cwd = (Get-Location).Path,
    [switch]$Pretty
)
. "$PSScriptRoot/OrquestaCommon.ps1"

$cfg = Get-OrquestaConfig -Cwd $Cwd
if ($Pretty) { $cfg | ConvertTo-Json -Depth 10 } else { $cfg | ConvertTo-Json -Depth 10 -Compress }
