<#
.SYNOPSIS
  Ejecuta un rol de orquesta con OpenAI Codex CLI (`codex exec`) en lugar de un subagente de Claude.
  Fable/Opus planea y revisa; Codex implementa. BRIEF, PLAN y formato REPORTE son los mismos que con Claude.

  - Aplica las mismas compuertas que Gate-Delegacion (PLAN en ejecución + BRIEF) para roles que escriben.
  - Inyecta como instrucciones el cuerpo del agente correspondiente (agents/<rol>.md), así el rol es idéntico en ambos motores.
  - Escribe el reporte en .orquesta/reportes/<TIPO>-NN-codex.md, registra spawn/stop (con tokens) en la bitácora
    y guarda el thread_id para que los reintentos usen `codex exec resume <id>` conservando el contexto.
  - Imprime el reporte final por stdout para el arquitecto.

.EXAMPLE
  pwsh -NoProfile -File scripts/Invoke-Codex.ps1 -Rol implementador -Brief .orquesta/briefs/BRIEF-01.md -Intento 1
  pwsh -NoProfile -File scripts/Invoke-Codex.ps1 -Rol implementador -Brief .orquesta/briefs/BRIEF-01.md -Intento 2 -Hallazgos .orquesta/reportes/REVISION-01.md
  pwsh -NoProfile -File scripts/Invoke-Codex.ps1 -Rol revisor -Brief .orquesta/briefs/BRIEF-01.md -Insumo .orquesta/reportes/REPORTE-01-codex.md
  pwsh -NoProfile -File scripts/Invoke-Codex.ps1 -Rol cartografo -Tarea "Mapeá lo relevante a: exportar cierres de caja a CSV"
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('implementador', 'implementador-senior', 'revisor', 'auditor-seguridad', 'documentador', 'cartografo')]
    [string]$Rol,
    [string]$Brief,
    [string]$Insumo,
    [string]$Hallazgos,
    [int]$Intento = 1,
    [string]$Tarea,
    [string]$Cwd = (Get-Location).Path,
    [string]$Modelo,
    [switch]$SinResume
)
. "$PSScriptRoot/OrquestaCommon.ps1"

function Fail-Codex([string]$Mensaje) {
    # Mensaje limpio por stderr y exit 2 (con ErrorActionPreference=Stop, Write-Error abortaría con exit 1).
    [Console]::Error.WriteLine($Mensaje)
    exit 2
}

$cfg   = Get-OrquestaConfig -Cwd $Cwd
$root  = Get-OrquestaPluginRoot
$mot   = Get-Prop $cfg 'motores.codex'
if ($null -eq $mot) { Fail-Codex "orquesta/codex: falta la sección motores.codex en la config." }
$trab  = Get-Prop $cfg "trabajadores.$Rol"
# Modelo: -Modelo explícito > modelo del trabajador si está configurado con motor codex > default del motor.
# Un alias de Claude (sonnet/opus/…) nunca se le pasa a Codex.
if (-not $Modelo) {
    $Modelo = if ("$(Get-Prop $trab 'motor')" -eq 'codex') { "$(Get-Prop $trab 'modelo')" } else { "$(Get-Prop $mot 'modelo')" }
}
if ($Modelo -in @('haiku', 'sonnet', 'opus', 'fable', 'inherit')) { $Modelo = "$(Get-Prop $mot 'modelo')" }

# ---- Compuertas (misma política que Gate-Delegacion) ----
$escritores = @('implementador', 'implementador-senior', 'documentador')
if ($Rol -in $escritores -and (Test-OrquestaGatesEnabled) -and (Get-Prop $cfg 'compuertas.delegacion')) {
    $plan = Get-PlanInfo -Cwd $Cwd -Config $cfg
    if (-not $plan.Existe) { Fail-Codex "orquesta/codex: no existe $(Get-Prop $cfg 'rutas.plan'). Creá el PLAN (Initialize-Orquesta.ps1), presentalo y ponelo en 'estado: en-ejecucion' antes de delegar." }
    if ($plan.Estado -notin @('en-ejecucion', 'pausado')) { Fail-Codex "orquesta/codex: el PLAN está en 'estado: $($plan.Estado)'. Solo se delega implementación con 'en-ejecucion' (o 'pausado')." }
    if ($Rol -ne 'documentador' -and -not $Brief) { Fail-Codex "orquesta/codex: el rol $Rol requiere -Brief <ruta a .orquesta/briefs/BRIEF-NN.md>." }
}
if ($Brief) {
    $briefPath = if ([IO.Path]::IsPathRooted($Brief)) { $Brief } else { Join-Path $Cwd $Brief }
    if (-not (Test-Path -LiteralPath $briefPath)) { Fail-Codex "orquesta/codex: no existe el BRIEF $briefPath." }
    if ($Rol -in @('implementador', 'implementador-senior') -and (Test-OrquestaGatesEnabled) -and (Get-Prop $cfg 'compuertas.delegacion')) {
        $forma = Test-BriefShape -Path $briefPath
        if (-not $forma.Valido) { Fail-Codex ("orquesta/codex: el BRIEF no pasa la validación de forma: " + ($forma.Problemas -join ' · ') + ". Corregilo y comprobá con scripts/Test-Brief.ps1.") }
    }
}

# ---- Identificadores y rutas ----
$nn = if ($Brief -and ($Brief -match 'BRIEF-(\d+)')) { $Matches[1] } else { (Get-Date).ToString('yyyyMMdd-HHmmss') }
$tipo = switch ($Rol) { 'revisor' { 'REVISION' } 'auditor-seguridad' { 'AUDITORIA' } 'cartografo' { 'MAPA' } 'documentador' { 'DOCS' } default { 'REPORTE' } }
$reportes = Join-Path $Cwd (Get-Prop $cfg 'rutas.reportes')
New-Item -ItemType Directory -Path $reportes -Force | Out-Null
$outFile   = Join-Path $reportes "$tipo-$nn-codex.md"
$jsonlFile = Join-Path $reportes ".codex-$tipo-$nn.jsonl"
$errFile   = Join-Path $reportes ".codex-$tipo-$nn.log"
$stateFile = Join-Path $reportes ".codex-$tipo-$nn.json"
$state = Read-OrquestaJsonFile -Path $stateFile

# ---- Prompt (forma recomendada para GPT-5.x/Codex: bloques XML, contrato de salida explícito) ----
$agentPath = Join-Path $root "agents/$Rol.md"
$agentLines = Get-Content -LiteralPath $agentPath -Encoding UTF8
$cuerpo = New-Object System.Collections.Generic.List[string]
$enFm = $false; $fmCerrado = $false
foreach ($l in $agentLines) {
    if (-not $fmCerrado) {
        if ($l.Trim() -eq '---') { if ($enFm) { $fmCerrado = $true } else { $enFm = $true }; continue }
        if ($enFm) { continue }
    }
    $cuerpo.Add($l)
}
$rutaPlan = Get-Prop $cfg 'rutas.plan'
$maxLineas = Get-Prop $cfg 'limites.max_lineas_reporte'
$esImplementador = $Rol -in @('implementador', 'implementador-senior')
$esRevisor = $Rol -in @('revisor', 'auditor-seguridad')
$usaEsquema = ($esImplementador -or $esRevisor) -and ((Get-Prop $mot 'salida_estructurada') -ne $false)
$schemaPath = if ($usaEsquema) { Join-Path $root ("schemas/" + $(if ($esRevisor) { 'revision' } else { 'reporte' }) + ".schema.json") } else { $null }

$b = New-Object System.Collections.Generic.List[string]
$b.Add("<role_instructions>")
$b.Add("Actuás como el rol '$Rol' del protocolo orquesta dentro del repositorio actual. No hablás con el usuario: tu salida la lee el arquitecto.")
$b.Add("Donde las instrucciones mencionen 'memoria de agente', ignorá esa parte: no aplica en este motor.")
$b.Add(""); $b.AddRange($cuerpo); $b.Add("</role_instructions>"); $b.Add("")
$b.Add("<task>")
if ($Brief)  { $b.Add("Ejecutar o verificar el BRIEF '$Brief' (leelo completo antes de nada). El plan general está en '$rutaPlan'. Intento: $Intento.") }
if ($Insumo) { $b.Add("Insumo a revisar: '$Insumo'.") }
if ($Tarea)  { $b.Add($Tarea) }
if ($Hallazgos) { $b.Add("Es un reintento: en '$Hallazgos' están los hallazgos del revisor sobre el intento anterior. Resolvé cada uno o explicá por qué no aplica.") }
$b.Add("Terminado significa: cada criterio de aceptación del BRIEF verificado con evidencia (archivo:línea, salida de comando o test), o marcado explícitamente como no cumplido.")
$b.Add("</task>"); $b.Add("")
$b.Add("<default_follow_through_policy>")
$b.Add("Seguí adelante sin preguntar en decisiones rutinarias (nombres internos, orden de pasos, detalles de estilo) y declaralas en el reporte. Detenete con estado BLOQUEADO solo si una ambigüedad cambiaría el contrato, los datos o el alcance, y formulá la pregunta exacta.")
$b.Add("</default_follow_through_policy>"); $b.Add("")
if ($esImplementador -or $Rol -eq 'documentador') {
    $b.Add("<action_safety>")
    $b.Add("Alcance = el BRIEF. No toques archivos listados como 'NO tocar' ni hagas refactors, renombres o mejoras no pedidas: van a 'propuestas'. No hagas git commit ni git push. No agregues dependencias sin declararlas como propuesta.")
    $b.Add("</action_safety>"); $b.Add("")
}
$b.Add("<verification_loop>")
if ($esRevisor) { $b.Add("No confíes en el reporte del trabajador: mirá el diff real, ejecutá vos los comandos de 'Cómo verificar' y comprobá cada criterio. Un criterio sin evidencia observada es no cumplido.") }
else { $b.Add("Ejecutá exactamente los comandos de 'Cómo verificar' del BRIEF y pegá el resultado resumido. No afirmes que algo funciona sin haberlo ejecutado.") }
$b.Add("</verification_loop>"); $b.Add("")
$b.Add("<grounding_rules>")
$b.Add("Toda afirmación sobre el código cita archivo y línea. Si algo es hipótesis, decilo. No inventes rutas ni resultados.")
$b.Add("</grounding_rules>"); $b.Add("")
if ($usaEsquema) {
    $b.Add("<structured_output_contract>")
    $b.Add("Tu mensaje final debe ser únicamente el JSON que cumple el esquema de salida provisto: sin texto antes ni después, sin Markdown. 'criterios' lleva un elemento por criterio del BRIEF, en orden. Detalle largo (logs, diffs) va a archivos en '$(Get-Prop $cfg 'rutas.reportes')/' y se cita por ruta.")
    $b.Add("</structured_output_contract>")
} else {
    $b.Add("<compact_output_contract>")
    $b.Add("Tu mensaje final es solo el reporte con el formato indicado en las instrucciones del rol, máximo $maxLineas líneas. El detalle largo va a '$(Get-Prop $cfg 'rutas.reportes')/' y se cita por ruta.")
    $b.Add("</compact_output_contract>")
}
$prompt = ($b -join "`n")

# ---- Comando codex ----
$cmd = "$(Get-Prop $mot 'comando')"; if (-not $cmd) { $cmd = 'codex' }
$esGit = $false
try { & git -C $Cwd rev-parse --is-inside-work-tree 2>$null | Out-Null; $esGit = ($LASTEXITCODE -eq 0) } catch { }

$args_ = @('exec', '--json', '--sandbox', "$(Get-Prop $mot 'sandbox')", '-C', $Cwd, '-o', $outFile)
if ($Modelo) { $args_ += @('-m', $Modelo) }
$razon = "$(Get-Prop $mot 'razonamiento')"
if ($razon) { $args_ += @('-c', "model_reasoning_effort=`"$razon`"") }
if ($schemaPath) { $args_ += @('--output-schema', $schemaPath) }
if (-not $esGit) { $args_ += '--skip-git-repo-check' }
$extra = Get-Prop $mot 'args_extra'; if ($extra) { $args_ += @($extra) }


$threadPrevio = if ($state) { "$(Get-Prop $state 'thread_id')" } else { '' }
$usaResume = ($Intento -gt 1) -and $threadPrevio -and -not $SinResume
if ($usaResume) {
    # Prompt corto por argumento (seguro para shims .cmd); el contenido completo va a un archivo.
    $reintentoFile = Join-Path $reportes "REINTENTO-$nn-$Intento.md"
    Set-Content -LiteralPath $reintentoFile -Value $prompt -Encoding UTF8
    $args_ += @('resume', $threadPrevio, "Leé el archivo '$reintentoFile' y aplicá lo que indica. Tu último mensaje debe ser solo el reporte.")
} else {
    $args_ += '-'   # prompt por stdin
}

Add-BitacoraEntry -Cwd $Cwd -Config $cfg -Entry @{
    evento = 'spawn'; sesion = 'codex'; agente = $Rol; motor = 'codex'; modelo = $(if ($Modelo) { $Modelo } else { 'codex-default' })
    chars_prompt = $prompt.Length; descripcion = "$tipo-$nn intento $Intento$(if ($usaResume) { ' (resume)' })"
}

$inicio = Get-Date
$exit = 0
$ErrorActionPreference = 'Continue'            # el stderr de codex no debe convertirse en excepción
$PSNativeCommandUseErrorActionPreference = $false
try {
    if ($cmd -like '*.ps1') {
        if ($usaResume) { & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $cmd @args_ 2> $errFile | Set-Content -LiteralPath $jsonlFile -Encoding UTF8 }
        else { $prompt | & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $cmd @args_ 2> $errFile | Set-Content -LiteralPath $jsonlFile -Encoding UTF8 }
    } else {
        if ($usaResume) { & $cmd @args_ 2> $errFile | Set-Content -LiteralPath $jsonlFile -Encoding UTF8 }
        else { $prompt | & $cmd @args_ 2> $errFile | Set-Content -LiteralPath $jsonlFile -Encoding UTF8 }
    }
    $exit = $LASTEXITCODE
} catch {
    $exit = 1
    Add-Content -LiteralPath $errFile -Value "orquesta/codex: no se pudo ejecutar '$cmd': $($_.Exception.Message)" -Encoding UTF8
}
$dur = [int]((Get-Date) - $inicio).TotalSeconds
$ErrorActionPreference = 'Stop'

# ---- Parseo del JSONL: thread_id, tokens, último mensaje ----
$threadId = $threadPrevio; $tokIn = $null; $tokOut = $null; $ultimoMsg = ''
if (Test-Path -LiteralPath $jsonlFile) {
    foreach ($l in (Get-Content -LiteralPath $jsonlFile -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($l) -or -not $l.TrimStart().StartsWith('{')) { continue }
        try { $ev = $l | ConvertFrom-Json } catch { continue }
        $tid = Get-Prop $ev 'thread_id'; if ($tid) { $threadId = "$tid" }
        $u = Get-Prop $ev 'usage'
        if ($u) { $tokIn = Get-Prop $u 'input_tokens'; $tokOut = Get-Prop $u 'output_tokens' }
        $item = Get-Prop $ev 'item'
        if ($item -and "$(Get-Prop $item 'type')" -eq 'agent_message') { $t = Get-Prop $item 'text'; if ($t) { $ultimoMsg = "$t" } }
    }
}
$crudo = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 } else { $ultimoMsg }
if (-not $crudo) { $crudo = '' }

# Salida estructurada: si el mensaje final es JSON válido, se guarda como .json y se renderiza al formato REPORTE/REVISIÓN.
$reporte = $crudo; $jsonSalida = $null; $estructurado = $false
if ($usaEsquema -and $crudo.TrimStart().StartsWith('{')) {
    try { $jsonSalida = $crudo | ConvertFrom-Json } catch { $jsonSalida = $null }
    if ($jsonSalida) {
        $estructurado = $true
        $jsonFile = [IO.Path]::ChangeExtension($outFile, '.json')
        Set-Content -LiteralPath $jsonFile -Value $crudo -Encoding UTF8
        $titulo = "$tipo — BRIEF-$nn"
        $reporte = if ($esRevisor) { ConvertTo-RevisionMarkdown -Json $jsonSalida -Titulo $titulo -Intento $Intento } else { ConvertTo-ReporteMarkdown -Json $jsonSalida -Titulo $titulo -Intento $Intento }
        Set-Content -LiteralPath $outFile -Value $reporte -Encoding UTF8
    }
}
if (-not (Test-Path -LiteralPath $outFile) -and $reporte) { Set-Content -LiteralPath $outFile -Value $reporte -Encoding UTF8 }

$estado = if ($estructurado) {
    $e = Get-Prop $jsonSalida 'estado'; if (-not $e) { $e = Get-Prop $jsonSalida 'dictamen' }; "$e"
} elseif ($reporte -match '(?i)\bBLOQUEADO\b') { 'BLOQUEADO' } elseif ($reporte -match '(?i)\bRECHAZADO\b') { 'RECHAZADO' } elseif ($reporte -match '(?i)\bAPROBADO\b') { 'APROBADO' } elseif ($reporte -match '(?i)\bCOMPLETADO\b') { 'COMPLETADO' } elseif ($reporte -match '(?i)\bPARCIAL\b') { 'PARCIAL' } else { '' }
if ($exit -ne 0) { $estado = 'ERROR' }

@{ thread_id = $threadId; intentos = $Intento; ultimo = (Get-Date).ToString('o'); modelo = $Modelo; rol = $Rol } | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding UTF8
Add-BitacoraEntry -Cwd $Cwd -Config $cfg -Entry @{
    evento = 'stop'; sesion = 'codex'; agente = $Rol; motor = 'codex'; agent_id = $threadId; estado = $estado
    lineas_reporte = $(if ($reporte) { @($reporte -split "`r?`n").Count } else { 0 }); chars_reporte = "$reporte".Length
    tokens_in = $tokIn; tokens_out = $tokOut; segundos = $dur; exit = $exit; estructurado = $estructurado
}

# ---- Salida para el arquitecto ----
$rel = Get-RelativePathSafe -Path $outFile -Base $Cwd
Write-Output "orquesta/codex · rol=$Rol · $tipo-$nn · intento=$Intento$(if ($usaResume) { ' (resume)' }) · modelo=$(if ($Modelo) { $Modelo } else { 'codex-default' }) · estado=$estado · ${dur}s · tokens=$(if ($null -ne $tokIn) { "$tokIn/$tokOut" } else { 'n/d' }) · salida=$(if ($estructurado) { 'json→markdown' } else { 'texto' }) · reporte=$rel"
if ($exit -ne 0) {
    Write-Output "codex exec terminó con código $exit. Últimas líneas de stderr ($errFile):"
    if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Tail 15 }
    exit 1
}
Write-Output ""
Write-Output $reporte
exit 0
