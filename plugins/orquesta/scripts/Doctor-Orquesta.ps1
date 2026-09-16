<#
.SYNOPSIS
  Diagnóstico del entorno de orquesta: PowerShell, plugin, hooks, config, Codex CLI (si algún trabajador lo usa),
  plugin oficial de OpenAI (opcional), graphify, git y estado del proyecto. Salida en Markdown. Exit 0 aunque haya avisos.
.EXAMPLE
  pwsh -NoProfile -File scripts/Doctor-Orquesta.ps1
#>
param([string]$Cwd = (Get-Location).Path)
. "$PSScriptRoot/OrquestaCommon.ps1"
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

$root = Get-OrquestaPluginRoot
$out = New-Object System.Collections.Generic.List[string]
$siguientes = New-Object System.Collections.Generic.List[string]
function Linea([bool]$ok, [string]$texto, [string]$aviso = '') {
    $script:out.Add("- $(if ($ok) { '✓' } else { '✗' }) $texto")
    if (-not $ok -and $aviso) { $script:siguientes.Add($aviso) }
}
function Version-De([string]$cmd, [string[]]$args_ = @('--version')) {
    try { $v = (& $cmd @args_ 2>&1 | Select-Object -First 1); if ($LASTEXITCODE -eq 0 -or $v) { return "$v".Trim() } } catch { }
    return $null
}

$out.Add('### Doctor orquesta')
# PowerShell
$psv = $PSVersionTable.PSVersion
Linea ($psv.Major -ge 7) "PowerShell $psv $(if ($psv.Major -lt 7) { '(se requiere 7+)' })" 'Instalá PowerShell 7: winget install Microsoft.PowerShell'
$pwshEnPath = $null -ne (Get-Command pwsh -ErrorAction SilentlyContinue)
Linea $pwshEnPath "pwsh en PATH $(if ($pwshEnPath) { '(los hooks lo necesitan)' } else { '— los hooks del plugin no van a correr' })" 'Agregá pwsh al PATH o reinstalá PowerShell 7 con la opción de PATH'

# Plugin y hooks
$hooksPath = Join-Path $root 'hooks/hooks.json'
$hooksOk = $false; $nHooks = 0
try { $h = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json; foreach ($ev in $h.hooks.PSObject.Properties) { $nHooks += @($ev.Value).Count }; $hooksOk = $nHooks -gt 0 } catch { }
Linea $hooksOk "hooks.json válido ($nHooks compuertas) en ``$root``"
$agentes = @(Get-ChildItem (Join-Path $root 'agents') -Filter *.md -ErrorAction SilentlyContinue).Count
Linea ($agentes -ge 6) "$agentes agentes en agents/"
$scriptsFaltan = @(@('Gate-Delegacion','Gate-Edicion','Gate-Cierre','Log-Delegacion','Aviso-Sesion','Show-Estado','Initialize-Orquesta','Initialize-OrquestaConfig','Test-Brief','Invoke-Codex') | Where-Object { -not (Test-Path (Join-Path $root "scripts/$_.ps1")) })
Linea ($scriptsFaltan.Count -eq 0) "scripts completos$(if ($scriptsFaltan) { ' — faltan: ' + ($scriptsFaltan -join ', ') })"
Linea (Test-OrquestaGatesEnabled) "compuertas $(if (Test-OrquestaGatesEnabled) { 'activas' } else { 'APAGADAS por ORQUESTA_GATES=0' })"

# Config
$cfg = $null
try { $cfg = Get-OrquestaConfig -Cwd $Cwd } catch { }
Linea ($null -ne $cfg) "config efectiva cargada$(if ($cfg) { ' — fuentes: ' + (($cfg._fuentes | ForEach-Object { Split-Path $_ -Leaf }) -join ', ') })" 'Revisá que .claude/orquesta.json y ~/.claude/orquesta.json sean JSON válido'
$usaCodex = $false
if ($cfg) {
    $modelosRaros = @()
    foreach ($p in $cfg.trabajadores.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }
        $motor = "$(Get-Prop $p.Value 'motor')"; if (-not $motor) { $motor = 'claude' }
        if ($motor -eq 'codex') { $usaCodex = $true }
        if ($motor -notin @('claude', 'codex')) { $modelosRaros += "$($p.Name): motor '$motor' desconocido" }
        if ($motor -eq 'claude' -and "$(Get-Prop $p.Value 'modelo')" -eq '') { $modelosRaros += "$($p.Name): sin modelo" }
    }
    Linea ($modelosRaros.Count -eq 0) "trabajadores configurados $(if ($usaCodex) { '(algunos en motor codex)' } else { '(todos en Claude)' })$(if ($modelosRaros) { ' — ' + ($modelosRaros -join '; ') })"
    if (-not (Test-Path -LiteralPath (Join-Path $Cwd '.claude/orquesta.json'))) {
        $out.Add("- ○ config del proyecto: no hay .claude/orquesta.json (se usan los defaults del plugin). Para crear uno editable, pre-llenado desde tu CLAUDE.md: /orquesta:init")
    }
}

# Codex (solo si se usa)
if ($usaCodex) {
    $cmdCodex = "$(Get-Prop $cfg 'motores.codex.comando')"; if (-not $cmdCodex) { $cmdCodex = 'codex' }
    $hayCodex = if ($cmdCodex -like '*.ps1') { Test-Path -LiteralPath $cmdCodex } else { $null -ne (Get-Command $cmdCodex -ErrorAction SilentlyContinue) }
    $ver = if ($hayCodex -and $cmdCodex -notlike '*.ps1') { Version-De $cmdCodex } else { $null }
    Linea $hayCodex "Codex CLI ($cmdCodex) $(if ($ver) { $ver } elseif ($hayCodex) { 'disponible' } else { 'NO encontrado' })" 'Instalá Codex CLI: npm i -g @openai/codex ; luego codex login'
    if ($hayCodex -and $cmdCodex -notlike '*.ps1') {
        $login = $null
        try { $login = (& $cmdCodex login status 2>&1 | Select-Object -First 1) } catch { }
        $logueado = $login -and ("$login" -notmatch '(?i)not logged|no.*sesi')
        Linea $logueado "login de Codex: $(if ($login) { "$login".Trim() } else { 'no se pudo determinar' })" 'Ejecutá: codex login (o codex login --device-auth)'
    }
    Linea (Test-Path (Join-Path $root 'schemas/reporte.schema.json')) "esquemas de salida estructurada presentes (schemas/)"
    $riesgos = @(Get-OverridesRiesgosos -Cwd $Cwd)
    Linea ($riesgos.Count -eq 0) "$(if ($riesgos.Count -eq 0) { 'motores.codex.comando/args_extra/sandbox no vienen del proyecto' } else { 'el .claude/orquesta.json del proyecto redefine ' + ($riesgos -join ' · ') + ' (viaja con el repo: en un clon ajeno decide qué ejecutable corre)' })" 'Revisá motores.codex.* en .claude/orquesta.json antes de delegar; si es tuyo, movelo a ~/.claude/orquesta.json'
}

# Plugin oficial de OpenAI (opcional)
$claudeDir = Join-Path $(if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }) '.claude'
$companion = $null
try { $companion = Get-ChildItem -Path (Join-Path $claudeDir 'plugins') -Recurse -Filter 'codex-companion.mjs' -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { }
$out.Add("- $(if ($companion) { '✓' } else { '○' }) plugin oficial de OpenAI (codex@openai-codex): $(if ($companion) { 'instalado — /codex:review y /codex:adversarial-review disponibles' } else { 'no instalado (opcional: /plugin marketplace add openai/codex-plugin-cc)' })")

# graphify / Obsidian / git en el proyecto (solo si la config cargó: sin ella no hay rutas que resolver)
$gfCmd = $null -ne (Get-Command graphify -ErrorAction SilentlyContinue)
if ($cfg) {
    $gfDir = Join-Path $Cwd (Get-Prop $cfg 'contexto.graphify.salida')
    $out.Add("- $(if (Test-Path $gfDir) { '✓' } else { '○' }) graphify: $(if (Test-Path $gfDir) { "grafo en $(Get-Prop $cfg 'contexto.graphify.salida')/" + $(if (Test-Path (Join-Path $gfDir 'needs_update')) { ' (desactualizado)' } else { '' }) } else { 'sin grafo en este proyecto' })$(if ($gfCmd) { ' · CLI disponible' } else { ' · CLI no encontrado (opcional)' })")
    if (-not (Get-Prop $cfg 'contexto.obsidian.usar')) {
        $out.Add("- ○ Obsidian: desactivado (contexto.obsidian.usar: false)")
    } else {
        $dec = Resolve-ObsidianPath -Cwd $Cwd -Config $cfg -Valor (Get-Prop $cfg 'contexto.obsidian.carpeta_decisiones')
        $enMd = Get-ObsidianDesajusteClaudeMd -Cwd $Cwd -RutaResuelta $dec
        if ($enMd) {
            Linea $false "Obsidian: la config resuelve a ``$dec`` pero el CLAUDE.md del proyecto dice ``$enMd``" 'Corré /orquesta:init (toma la carpeta de Obsidian del CLAUDE.md y te pregunta antes de escribir) o poné contexto.obsidian.carpeta_decisiones en .claude/orquesta.json'
        } else {
            $out.Add("- $(if ($dec -and (Test-Path $dec)) { '✓' } else { '○' }) Obsidian: carpeta de decisiones ``$dec`` $(if ($dec -and (Test-Path $dec)) { 'existe' } else { 'aún no existe (se crea al cerrar el primer PLAN)' })")
        }
    }
}
$gitOk = $false; try { & git -C $Cwd rev-parse --is-inside-work-tree 2>$null | Out-Null; $gitOk = ($LASTEXITCODE -eq 0) } catch { }
Linea $gitOk "git: $(if ($gitOk) { 'repositorio detectado' } else { 'este directorio no es un repo git (Codex necesitará --skip-git-repo-check; ya lo agrega el wrapper)' })"
if ($cfg) {
    $plan = Get-PlanInfo -Cwd $Cwd -Config $cfg
    $out.Add("- ○ PLAN: $(if ($plan.Existe) { "estado $($plan.Estado), $($plan.Abiertos) abiertas" } else { 'ninguno en este proyecto' })")
}

if ($siguientes.Count -gt 0) { $out.Add(''); $out.Add('### Siguientes pasos'); foreach ($s in $siguientes | Select-Object -Unique) { $out.Add("1. $s") } }
$out -join "`n"
exit 0
