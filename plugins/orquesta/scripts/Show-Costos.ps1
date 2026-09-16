<#
.SYNOPSIS
  Costo nominal de la orquestación, medido: lee el `usage` real de cada request en los transcripts de Claude Code
  (sesión del arquitecto + subagentes) y los tokens de Codex de la bitácora, y lo valora con costos.tarifas.
  Sin esto, el arquitecto estima a ojo y se equivoca por 2-3x (los `subagent_tokens` de las notificaciones no
  incluyen lecturas de caché ni thinking).

  Sesiones: -Sesion <id>[,<id>] o, por defecto, las que aparecen en .orquesta/bitacora.jsonl (campo `sesion` de los
  hooks). Si la bitácora no tiene ninguna, el transcript más reciente del proyecto.
.EXAMPLE
  pwsh -NoProfile -File scripts/Show-Costos.ps1
  pwsh -NoProfile -File scripts/Show-Costos.ps1 -Sesion 2c954fcd-9d8b-4318-bb2d-dbceb1e429d3 -Json
#>
param(
    [string]$Cwd = (Get-Location).Path,
    [string[]]$Sesion = @(),
    [string]$ClaudeDir = '',
    [switch]$Json
)
. "$PSScriptRoot/OrquestaCommon.ps1"

$cfg = Get-OrquestaConfig -Cwd $Cwd
if (-not $ClaudeDir) { $ClaudeDir = Get-ClaudeConfigDir }
$projDir = Join-Path (Join-Path $ClaudeDir 'projects') (ConvertTo-ClaudeProjectSlug -Path $Cwd)

# ---- Bitácora: sesiones, roles de subagentes (agent_id -> agente), corridas de Codex
$entries = @()
$bit = Join-Path $Cwd (Get-Prop $cfg 'rutas.bitacora')
if (Test-Path -LiteralPath $bit) {
    foreach ($l in (Get-Content -LiteralPath $bit -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        try { $entries += ($l | ConvertFrom-Json) } catch { }
    }
}
$roles = @{}
foreach ($e in $entries) {
    $aid = "$(Get-Prop $e 'agent_id')"; $ag = "$(Get-Prop $e 'agente')"
    if ($aid -and $ag -and "$(Get-Prop $e 'motor')" -ne 'codex' -and -not $roles.ContainsKey($aid)) { $roles[$aid] = $ag }
}
$sesiones = @($Sesion | Where-Object { $_ })
$origenSesiones = 'indicadas'
if ($sesiones.Count -eq 0) {
    $sesiones = @($entries | ForEach-Object { "$(Get-Prop $_ 'sesion')" } | Where-Object { $_ -and $_ -ne 'codex' } | Select-Object -Unique)
    $origenSesiones = 'bitácora'
}
if ($sesiones.Count -eq 0 -and (Test-Path -LiteralPath $projDir)) {
    $ult = Get-ChildItem -LiteralPath $projDir -Filter '*.jsonl' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($ult) { $sesiones = @($ult.BaseName); $origenSesiones = 'transcript más reciente' }
}

# ---- Requests del arquitecto y de los subagentes
$arq = @(); $subs = @(); $faltantes = @()
foreach ($s in $sesiones) {
    $main = Join-Path $projDir "$s.jsonl"
    if (Test-Path -LiteralPath $main) { $arq += @(Read-ClaudeTranscriptUsage -Path $main) } else { $faltantes += $s }
    $subDir = Join-Path (Join-Path $projDir $s) 'subagents'
    if (Test-Path -LiteralPath $subDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $subDir -Filter '*.jsonl' -File)) {
            $aid = $f.BaseName -replace '^agent-', ''
            $rol = if ($roles.ContainsKey($aid)) { $roles[$aid] } else { 'subagente' }
            foreach ($r in @(Read-ClaudeTranscriptUsage -Path $f.FullName)) {
                $subs += [pscustomobject]@{ rol = $rol; agent_id = $aid; ts = $r.ts; model = $r.model; in = $r.in; cc = $r.cc; cr = $r.cr; out = $r.out }
            }
        }
    }
}

function Suma($coll, [string]$prop) {
    # Measure-Object sobre una colección vacía no tiene .Sum (StrictMode lo convierte en error): acá vacío = 0.
    $items = @($coll); if ($items.Count -eq 0) { return 0 }
    return ($items | Measure-Object -Property $prop -Sum).Sum
}

function New-Fila([string]$actor, [string]$modelo, $reqs) {
    $fam = Get-FamiliaModelo -Modelo $modelo
    $in = Suma $reqs 'in'; $cc = Suma $reqs 'cc'; $cr = Suma $reqs 'cr'; $out = Suma $reqs 'out'
    $ctx = ($reqs | ForEach-Object { $_.in + $_.cc + $_.cr } | Measure-Object -Maximum).Maximum
    [pscustomobject]@{
        actor = $actor; modelo = $modelo; familia = $(if ($fam) { $fam } else { 'opus (asumida)' }); requests = @($reqs).Count
        ctx_max = [int64]$ctx; entrada = [int64]$in; cache_escritura = [int64]$cc; cache_lectura = [int64]$cr; salida = [int64]$out
        usd = Get-CostoTokens -Config $cfg -Familia $fam -In $in -Cc $cc -Cr $cr -Out $out
    }
}

$filas = @()
foreach ($g in ($arq | Group-Object model | Sort-Object Count -Descending)) { $filas += New-Fila 'arquitecto (sesión)' $g.Name $g.Group }
foreach ($g in ($subs | Group-Object { "$($_.rol)|$($_.model)" } | Sort-Object Name)) {
    $rol, $mod = $g.Name -split '\|', 2
    $n = @($g.Group | Select-Object -ExpandProperty agent_id -Unique).Count
    $filas += New-Fila "$rol x$n" $mod $g.Group
}
# Codex: la bitácora ya trae tokens_in/tokens_out por corrida (sesion = 'codex', no está ligado a la sesión de Claude).
$codexStops = @($entries | Where-Object { "$(Get-Prop $_ 'evento')" -eq 'stop' -and "$(Get-Prop $_ 'motor')" -eq 'codex' })
$codexModelos = @{}
foreach ($e in @($entries | Where-Object { "$(Get-Prop $_ 'evento')" -eq 'spawn' -and "$(Get-Prop $_ 'motor')" -eq 'codex' })) { $codexModelos["$(Get-Prop $e 'agente')"] = "$(Get-Prop $e 'modelo')" }
function Num($o, [string]$k) { $v = Get-Prop $o $k; if ($null -eq $v -or "$v" -eq '') { return 0L }; return [int64]$v }
foreach ($g in ($codexStops | Group-Object { "$(Get-Prop $_ 'agente')" })) {
    $tin = ($g.Group | ForEach-Object { Num $_ 'tokens_in' } | Measure-Object -Sum).Sum
    $tout = ($g.Group | ForEach-Object { Num $_ 'tokens_out' } | Measure-Object -Sum).Sum
    $mod = if ($codexModelos.ContainsKey($g.Name)) { $codexModelos[$g.Name] } else { 'codex' }
    $filas += [pscustomobject]@{
        actor = "$($g.Name) x$($g.Count) (codex)"; modelo = $mod; familia = 'codex'; requests = $g.Count; ctx_max = 0
        entrada = [int64]$tin; cache_escritura = 0; cache_lectura = 0; salida = [int64]$tout
        usd = Get-CostoTokens -Config $cfg -Familia 'codex' -In $tin -Out $tout
    }
}

# ---- Señales accionables
$frios = @($arq | Where-Object { $_.cc -ge 100000 })
$usdFrios = 0.0; foreach ($f in $frios) { $usdFrios += Get-CostoTokens -Config $cfg -Familia (Get-FamiliaModelo $f.model) -Cc $f.cc }
$total = [math]::Round([double](Suma $filas 'usd'), 2)
$usdArq = [math]::Round([double](Suma @($filas | Where-Object { $_.actor -like 'arquitecto*' }) 'usd'), 2)
$senales = [ordered]@{
    requests_arquitecto = @($arq).Count
    contexto_max_arquitecto = [int64]$(if ($arq.Count) { ($arq | ForEach-Object { $_.in + $_.cc + $_.cr } | Measure-Object -Maximum).Maximum } else { 0 })
    salida_arquitecto = [int64](Suma $arq 'out')
    usd_por_request_arquitecto = $(if ($arq.Count) { [math]::Round($usdArq / $arq.Count, 3) } else { 0 })
    arranques_en_frio = $frios.Count
    usd_arranques_en_frio = [math]::Round($usdFrios, 2)
    modelos_arquitecto = @($arq | Select-Object -ExpandProperty model -Unique)
}

if ($Json) {
    [pscustomobject]@{ cwd = $Cwd; transcripts = $projDir; sesiones = $sesiones; origen_sesiones = $origenSesiones; faltantes = $faltantes; filas = $filas; senales = $senales; total_usd = $total } | ConvertTo-Json -Depth 6
    return
}

function K([int64]$n) {
    # Cultura invariante: en es-* el -f pondría "2,0M" y la tabla dejaría de ser comparable.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    if ($n -ge 1000000) { return [string]::Format($inv, '{0:0.0}M', $n / 1e6) }
    if ($n -ge 1000) { return [string]::Format($inv, '{0:0}k', $n / 1e3) }
    return "$n"
}
$out = New-Object System.Collections.Generic.List[string]
$out.Add("### Costos de la orquestación (nominal, tarifa API)")
if ($sesiones.Count -eq 0) {
    $out.Add("No encontré sesiones: la bitácora no tiene campo ``sesion`` y no hay transcripts en ``$projDir``. Con ``-Sesion <id>`` podés indicar una a mano.")
    $out -join "`n"; return
}
$out.Add("Sesión(es) ($origenSesiones): " + (($sesiones | ForEach-Object { '`' + $_ + '`' }) -join ', ') + " · transcripts en ``$projDir``")
if ($faltantes.Count -gt 0) { $out.Add("Sin transcript (¿otra máquina o CLAUDE_CONFIG_DIR?): " + (($faltantes | ForEach-Object { '`' + $_ + '`' }) -join ', ')) }
$out.Add("")
$out.Add("| Actor | Modelo | Requests | Ctx máx | Entrada | Caché escrita | Caché leída | Salida | ≈ USD |")
$out.Add("|---|---|---|---|---|---|---|---|---|")
foreach ($f in $filas) {
    $ctxTxt = if ($f.ctx_max) { K $f.ctx_max } else { '—' }
    $out.Add("| $($f.actor) | $($f.modelo) | $($f.requests) | $ctxTxt | $(K $f.entrada) | $(K $f.cache_escritura) | $(K $f.cache_lectura) | $(K $f.salida) | $($f.usd) |")
}
$out.Add("| **Total** | | | | | | | | **$total** |")
$out.Add("")   # una tabla Markdown sigue hasta la primera línea vacía
if ($arq.Count) {
    $out.Add("Arquitecto: $($senales.requests_arquitecto) requests · contexto máximo $(K $senales.contexto_max_arquitecto) · salida $(K $senales.salida_arquitecto) (incluye thinking) · ≈ USD $($senales.usd_por_request_arquitecto) por request. Cada tool call es un request que relee todo el contexto: menos llamadas y contexto más chico es la palanca, no el modelo.")
    if ($frios.Count -gt 0) { $out.Add("**Arranques en frío:** $($frios.Count) request(s) re-escribieron >= 100k de caché (≈ USD $($senales.usd_arranques_en_frio)). Pasa al reanudar una sesión larga tras más de una hora o al cambiar de modelo con ``/model``: para retro, memoria o tareas laterales, sesión nueva o subagente.") }
    $asumidas = @($filas | Where-Object { $_.familia -like '*asumida*' })
    if ($asumidas.Count -gt 0) { $out.Add("Modelos sin tarifa propia (se usó la de opus): " + (($asumidas | ForEach-Object { $_.modelo } | Select-Object -Unique) -join ', ') + ". Agregalos en ``costos.tarifas``.") }
}
if ($codexStops.Count -gt 0) { $out.Add("Codex: tokens según ``codex exec`` (entrada incluye caché) valorados con ``costos.tarifas.codex``, de referencia; con plan Team consume créditos, no dólares.") }
$out.Add("Tarifas por millón en ``costos.tarifas`` de la config (defaults del plugin, editables por proyecto). Con suscripción es solo referencia; los tokens sí cuentan contra la cuota.")
$out -join "`n"
