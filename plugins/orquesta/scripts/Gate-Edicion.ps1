<#
.SYNOPSIS
  Compuerta PreToolUse(Edit|Write|MultiEdit|NotebookEdit): "el arquitecto no toca código".
  Mientras el PLAN está en `estado: en-ejecucion`, el hilo principal solo puede escribir en:
    .orquesta/**, .claude/**, carpetas de Obsidian configuradas, docs/** y archivos *.md.
  Todo lo demás debe delegarse a un implementador. Los subagentes (agent_id presente) no se restringen.
  Escape: `estado: pausado` en PLAN.md, o ORQUESTA_GATES=0, o compuertas.arquitecto_no_edita=false.
#>
. "$PSScriptRoot/OrquestaCommon.ps1"

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
if (Get-Prop $in 'agent_id') { exit 0 }
if (-not (Test-OrquestaGatesEnabled)) { exit 0 }

$cwd = Get-Prop $in 'cwd'; if (-not $cwd) { $cwd = (Get-Location).Path }
$cfg = Get-OrquestaConfig -Cwd $cwd
if (-not (Get-Prop $cfg 'compuertas.arquitecto_no_edita')) { exit 0 }

$plan = Get-PlanInfo -Cwd $cwd -Config $cfg
if (-not $plan.Existe -or $plan.Estado -ne 'en-ejecucion') { exit 0 }

$path = Get-Prop $in 'tool_input.file_path'
if (-not $path) { $path = Get-Prop $in 'tool_input.notebook_path' }
if (-not $path) { exit 0 }

$rel = (Get-RelativePathSafe -Path "$path" -Base $cwd)
$relLower = $rel.ToLowerInvariant()

$decRuta = Resolve-ObsidianPath -Cwd $cwd -Config $cfg -Valor (Get-Prop $cfg 'contexto.obsidian.carpeta_decisiones')
$hndRuta = Resolve-ObsidianPath -Cwd $cwd -Config $cfg -Valor (Get-Prop $cfg 'contexto.obsidian.carpeta_handoffs')
$permitidos = @(
    (Get-Prop $cfg 'rutas.raiz'),
    '.claude',
    'docs',
    $decRuta,
    $hndRuta
) | Where-Object { $_ } | ForEach-Object { ($_ -replace '\\', '/').Trim('/').ToLowerInvariant() }

foreach ($p in $permitidos) {
    if ($relLower -eq $p -or $relLower.StartsWith("$p/")) { exit 0 }
}
if ($relLower.EndsWith('.md')) { exit 0 }

Deny-ToolUse ("orquesta: PLAN en ejecución — el arquitecto no edita código ($rel). Delegá este cambio a orquesta:implementador " +
    "(o implementador-senior) con un BRIEF. Si es un ajuste realmente trivial y el usuario lo autoriza, poné 'estado: pausado' en el PLAN, " +
    "hacé el cambio y volvé a 'en-ejecucion'.")
