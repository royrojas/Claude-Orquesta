<#
.SYNOPSIS
  Estado compacto en Markdown para inyectar en los skills: enrutamiento efectivo, PLAN, graphify, Obsidian, bitácora.
.EXAMPLE
  pwsh -NoProfile -File scripts/Show-Estado.ps1
#>
param([string]$Cwd = (Get-Location).Path)
. "$PSScriptRoot/OrquestaCommon.ps1"

$cfg  = Get-OrquestaConfig -Cwd $Cwd
$plan = Get-PlanInfo -Cwd $Cwd -Config $cfg
$out  = New-Object System.Collections.Generic.List[string]

# --- Enrutamiento
$out.Add("### Enrutamiento efectivo")
$out.Add("Arquitecto (sesión): **$(Get-Prop $cfg 'orquestador.modelo')**  ·  compuertas: $(if (Test-OrquestaGatesEnabled) {'activas'} else {'APAGADAS (ORQUESTA_GATES=0)'})")
$out.Add("")
$out.Add("| Trabajador | Motor | Modelo | Esfuerzo |")
$out.Add("|---|---|---|---|")
$hayCodex = $false
foreach ($p in $cfg.trabajadores.PSObject.Properties) {
    if ($p.Name -like '_*') { continue }
    $motor = "$(Get-Prop $p.Value 'motor')"; if (-not $motor) { $motor = 'claude' }
    if ($motor -eq 'codex') { $hayCodex = $true }
    $modelo = "$(Get-Prop $p.Value 'modelo')"
    if ($motor -eq 'codex' -and ($modelo -in @('haiku','sonnet','opus','fable','inherit',''))) { $modelo = if ("$(Get-Prop $cfg 'motores.codex.modelo')") { "$(Get-Prop $cfg 'motores.codex.modelo')" } else { 'codex-default' } }
    $out.Add("| orquesta:$($p.Name) | $motor | $modelo | $($p.Value.esfuerzo) |")
}
if ($hayCodex) {
    $cmdCodex = "$(Get-Prop $cfg 'motores.codex.comando')"; if (-not $cmdCodex) { $cmdCodex = 'codex' }
    $disp = if ($cmdCodex -like '*.ps1') { Test-Path -LiteralPath $cmdCodex } else { $null -ne (Get-Command $cmdCodex -ErrorAction SilentlyContinue) }
    $out.Add("Motor codex: comando ``$cmdCodex`` $(if ($disp) {'disponible'} else {'**NO ENCONTRADO** (instalá Codex CLI y corré codex login)'}) · sandbox: $(Get-Prop $cfg 'motores.codex.sandbox') · razonamiento: $(Get-Prop $cfg 'motores.codex.razonamiento')")
}
$out.Add("Paralelo máx: $(Get-Prop $cfg 'limites.max_paralelo') · reporte máx: $(Get-Prop $cfg 'limites.max_lineas_reporte') líneas · reintentos/tarea: $(Get-Prop $cfg 'enrutamiento.max_reintentos_por_tarea')")
$fuentes = @($cfg._fuentes | Where-Object { $_ -notlike '*orquesta.defaults.json' })
if ($fuentes.Count -gt 0) { $out.Add("Overrides: " + ($fuentes -join ', ')) } else { $out.Add("Overrides: ninguno (solo defaults). Para cambiar modelos: .claude/orquesta.json o ~/.claude/orquesta.json") }
$out.Add("")

# --- PLAN
$out.Add("### PLAN")
if ($plan.Existe) {
    $out.Add("Existe ``$(Get-Prop $cfg 'rutas.plan')`` · estado: **$($plan.Estado)** · objetivo: $($plan.Objetivo)")
    $out.Add("Tareas: $($plan.Abiertos) abiertas · $($plan.Cerrados) cerradas · $($plan.Diferidos) diferidas · verificación final: $(if ($plan.VerificacionCerrada) {'cerrada'} else {'pendiente'})")
    if ($plan.Abiertos -gt 0) {
        $muestra = @($plan.ItemsAbiertos | Select-Object -First 6)
        $out.Add("Abiertas: " + (($muestra | ForEach-Object { '`' + $_ + '`' }) -join ' · ') + $(if ($plan.Abiertos -gt 6) { ' …' } else { '' }))
    }
} else {
    $out.Add("No hay PLAN en este proyecto. Flujo nuevo: cartógrafo → clarificar → Initialize-Orquesta.ps1 → briefs → delegar.")
}
$out.Add("")

# --- Contexto: graphify / Obsidian / git
$out.Add("### Contexto del proyecto")
$gfDir = Join-Path $Cwd (Get-Prop $cfg 'contexto.graphify.salida')
if ((Get-Prop $cfg 'contexto.graphify.usar') -and (Test-Path -LiteralPath $gfDir)) {
    $report = Join-Path $gfDir 'GRAPH_REPORT.md'
    $stale  = Test-Path -LiteralPath (Join-Path $gfDir 'needs_update')
    $out.Add("graphify: **disponible** ($(if (Test-Path $report) {'GRAPH_REPORT.md'} else {'sin GRAPH_REPORT.md'})$(if ($stale) {', DESACTUALIZADO → correr graphify update .'} else {''}))")
} else {
    $out.Add("graphify: no hay ``$(Get-Prop $cfg 'contexto.graphify.salida')/`` → el cartógrafo trabaja con grep/glob; considerá /graphify . (o tu skill de setup de proyecto)")
}
$dec = Join-Path $Cwd (Get-Prop $cfg 'contexto.obsidian.carpeta_decisiones')
$hnd = Join-Path $Cwd (Get-Prop $cfg 'contexto.obsidian.carpeta_handoffs')
$nDec = if (Test-Path -LiteralPath $dec) { @(Get-ChildItem -LiteralPath $dec -Filter '*.md' -File -ErrorAction SilentlyContinue).Count } else { -1 }
$out.Add("Obsidian: decisiones ``$(Get-Prop $cfg 'contexto.obsidian.carpeta_decisiones')/`` $(if ($nDec -ge 0) {"($nDec notas)"} else {'(no existe aún)'}) · handoffs ``$(Get-Prop $cfg 'contexto.obsidian.carpeta_handoffs')/`` $(if (Test-Path -LiteralPath $hnd) {'(existe)'} else {'(no existe aún)'})")
try {
    $branch = (& git -C $Cwd rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $branch) {
        $dirty = @(& git -C $Cwd status --porcelain 2>$null).Count
        $out.Add("git: rama ``$branch`` · $dirty archivo(s) con cambios sin commit")
    }
} catch { }
$out.Add("")

# --- Bitácora
$bit = Join-Path $Cwd (Get-Prop $cfg 'rutas.bitacora')
if (Test-Path -LiteralPath $bit) {
    $entries = @()
    foreach ($l in (Get-Content -LiteralPath $bit -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        try { $entries += ($l | ConvertFrom-Json) } catch { }
    }
    $spawns = @($entries | Where-Object { $_.evento -eq 'spawn' })
    if ($spawns.Count -gt 0) {
        $out.Add("### Bitácora de delegaciones (esta y sesiones anteriores)")
        $grp = $spawns | Group-Object { "$($_.agente) [$($_.modelo)]" } | Sort-Object Count -Descending
        $out.Add(($grp | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ' · ')
        $out.Add("")
    }
}

$out -join "`n"
