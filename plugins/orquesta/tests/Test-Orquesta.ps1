<#
.SYNOPSIS
  Pruebas del plugin orquesta. Sin dependencias (no requiere Pester).
  Valida: JSON de manifiestos y hooks, frontmatter de agentes y skills, sintaxis de todos los .ps1,
  y el comportamiento real de cada compuerta alimentándola con JSON como lo hace Claude Code.
.EXAMPLE
  pwsh -NoProfile -File tests/Test-Orquesta.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Misma política que OrquestaCommon.ps1: la suite compara strings con acentos y ✓/✗, así que la consola tiene que ser UTF-8
# también del lado del harness (si no, corrida desde Git Bash da fallos falsos).
try { $utf8 = [Text.UTF8Encoding]::new($false); [Console]::InputEncoding = $utf8; [Console]::OutputEncoding = $utf8; $OutputEncoding = $utf8 } catch { }

$Root    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Scripts = Join-Path $Root 'scripts'
$pwsh    = (Get-Process -Id $PID).Path
$fallos  = 0; $ok = 0

function Assert($cond, [string]$msg) {
    if ($cond) { $script:ok++; Write-Host "  ok   $msg" -ForegroundColor Green }
    else       { $script:fallos++; Write-Host "  FAIL $msg" -ForegroundColor Red }
}
function Invoke-Hook([string]$script, [hashtable]$input_, [hashtable]$env_ = @{}) {
    $json = $input_ | ConvertTo-Json -Depth 10 -Compress
    $prev = @{}
    foreach ($k in $env_.Keys) { $prev[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $env_[$k]) }
    try {
        $out = $json | & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts $script) 2>&1
        return (($out | Out-String).Trim())
    } finally {
        foreach ($k in $env_.Keys) { [Environment]::SetEnvironmentVariable($k, $prev[$k]) }
    }
}
function Get-Frontmatter([string]$path) {
    $lines = Get-Content -LiteralPath $path -Encoding UTF8
    if ($lines[0].Trim() -ne '---') { return $null }
    $fm = @{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }
        if ($lines[$i] -match '^([A-Za-z_-]+)\s*:\s*(.*)$') { $fm[$Matches[1]] = $Matches[2].Trim() }
    }
    return $fm
}

function New-BriefValido([string]$dir, [string]$nn) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $b = @(
        '---', "brief: BRIEF-$nn", 'tarea: "1. Exportar CSV"', 'tier: implementador', '---',
        "# BRIEF-$nn — Exportar CSV", '',
        '## Contexto mínimo', 'Servicio de cierres de caja.', '',
        '## Objetivo de la tarea', 'Agregar exportación CSV de cierres.', '',
        '## Archivos', '- Leer primero: `src/Cierres/CierreService.cs`', '- Modificar: `src/Cierres/CierreService.cs`', '- NO tocar: `src/Ventas/*` (otra tarea)', '',
        '## Contrato exacto', '```csharp', 'Task<string> ExportarCsvAsync(DateOnly desde, DateOnly hasta, CancellationToken ct);', '```', '',
        '## Criterios de aceptación (verificables)',
        '1. `ExportarCsvAsync` devuelve encabezado + una fila por cierre — test `CierreServiceTests.ExportaCsv`.',
        '2. Un rango inválido lanza `ArgumentException` — test `CierreServiceTests.RechazaRangoInvalido`.',
        '3. `dotnet build` sin warnings nuevos y `dotnet test --filter CierreServiceTests` en verde.', '',
        '## Cómo verificar', '```powershell', 'dotnet build src/Cierres.sln -warnaserror', 'dotnet test tests/Cierres.Tests.csproj --filter CierreServiceTests', '```', ''
    )
    Set-Content -LiteralPath (Join-Path $dir "BRIEF-$nn.md") -Value ($b -join "`n") -Encoding UTF8
}

Write-Host "`n== 1. JSON válido ==" -ForegroundColor Cyan
foreach ($f in @('.claude-plugin/plugin.json', 'hooks/hooks.json', 'config/orquesta.defaults.json', 'ejemplos/orquesta.json', 'ejemplos/orquesta-codex.json', '../../.claude-plugin/marketplace.json')) {
    $p = Join-Path $Root $f
    try { $null = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; Assert $true "$f parsea" } catch { Assert $false "$f parsea: $($_.Exception.Message)" }
}
$hooks = Get-Content (Join-Path $Root 'hooks/hooks.json') -Raw | ConvertFrom-Json
foreach ($ev in $hooks.hooks.PSObject.Properties) {
    foreach ($grupo in $ev.Value) { foreach ($h in $grupo.hooks) {
        $script = ($h.args | Where-Object { $_ -like '*.ps1' }) -replace '\$\{CLAUDE_PLUGIN_ROOT\}', $Root
        Assert (Test-Path $script) "hooks.json/$($ev.Name) apunta a un script existente ($(Split-Path $script -Leaf))"
    } }
}

Write-Host "`n== 2. Sintaxis PowerShell ==" -ForegroundColor Cyan
foreach ($ps1 in Get-ChildItem (Join-Path $Root 'scripts') -Filter *.ps1) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($ps1.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    Assert ($errors.Count -eq 0) "$($ps1.Name) sin errores de sintaxis$(if ($errors.Count) { ': ' + $errors[0].Message })"
}

Write-Host "`n== 3. Agentes ==" -ForegroundColor Cyan
$agentes = Get-ChildItem (Join-Path $Root 'agents') -Filter *.md
Assert ($agentes.Count -eq 6) "hay 6 agentes ($($agentes.Count))"
$defaults = Get-Content (Join-Path $Root 'config/orquesta.defaults.json') -Raw | ConvertFrom-Json
foreach ($a in $agentes) {
    $fm = Get-Frontmatter $a.FullName
    Assert ($null -ne $fm) "$($a.Name): frontmatter en la línea 1"
    if ($null -eq $fm) { continue }
    Assert ($fm.ContainsKey('name') -and $fm.name -match '^[a-z][a-z0-9-]*$') "$($a.Name): name válido ($($fm.name))"
    Assert ($fm.ContainsKey('description') -and $fm.description.Length -gt 40) "$($a.Name): description presente"
    Assert ($fm.ContainsKey('model')) "$($a.Name): model declarado ($($fm.model))"
    Assert ($null -ne $defaults.trabajadores.PSObject.Properties[$fm.name]) "$($a.Name): tiene entrada en trabajadores de la config"
    $body = Get-Content $a.FullName -Raw
    Assert (($body -split "`r?`n").Count -lt 120) "$($a.Name): prompt razonable (<120 líneas)"
}

Write-Host "`n== 4. Skills ==" -ForegroundColor Cyan
foreach ($s in Get-ChildItem (Join-Path $Root 'skills') -Directory) {
    $skill = Join-Path $s.FullName 'SKILL.md'
    Assert (Test-Path $skill) "skills/$($s.Name)/SKILL.md existe"
    $fm = Get-Frontmatter $skill
    Assert ($null -ne $fm -and $fm.ContainsKey('description')) "skills/$($s.Name): description en frontmatter"
    Assert ((Get-Content $skill).Count -lt 500) "skills/$($s.Name): menos de 500 líneas"
    if ($null -ne $fm -and $fm.ContainsKey('allowed-tools')) { Assert ($fm['allowed-tools'] -notmatch '\)\s+[A-Za-z]') "skills/$($s.Name): allowed-tools separado por comas" }
}
$skArq = Get-Content (Join-Path $Root 'skills/arquitecto/SKILL.md') -Raw -Encoding UTF8
Assert ($skArq -match '`inherit`' -and $skArq -match 'ID completo' -and $skArq -match '-Intento N\+1 -Hallazgos') "arquitecto: regla de model (inherit / ID completo) y reintento codex documentados"
Assert ($skArq -match 'preferencia permanente' -and $skArq -match 'AskUserQuestion' -and $skArq -match '\.claude/orquesta\.json' -and $skArq -match 'fusion') "arquitecto: pregunta antes de persistir un override permanente en orquesta.json"
foreach ($t in @('PLAN.md', 'BRIEF.md', 'REPORTE.md', 'ADR.md', 'HANDOFF.md')) { Assert (Test-Path (Join-Path $Root "skills/arquitecto/plantillas/$t")) "plantilla $t existe" }
foreach ($r in @('enrutamiento.md', 'brief-checklist.md', 'revision-checklist.md')) { Assert (Test-Path (Join-Path $Root "skills/arquitecto/referencias/$r")) "referencia $r existe" }

Write-Host "`n== 5. Config efectiva y merge ==" -ForegroundColor Cyan
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("orquesta-test-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmp '.claude') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmp 'src') -Force | Out-Null
Set-Content (Join-Path $tmp '.claude/orquesta.json') '{ "trabajadores": { "implementador": { "modelo": "opus" } }, "limites": { "max_paralelo": 5 } }'
$cfgJson = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Resolve-OrquestaConfig.ps1') -Cwd $tmp | ConvertFrom-Json
Assert ($cfgJson.trabajadores.implementador.modelo -eq 'opus') "override de proyecto reemplaza modelo del implementador"
Assert ($cfgJson.trabajadores.implementador.esfuerzo -eq 'medium') "merge profundo conserva claves no sobrescritas"
Assert ($cfgJson.trabajadores.revisor.modelo -eq 'opus') "otros trabajadores conservan defaults"
Assert ($cfgJson.limites.max_paralelo -eq 5) "override de límites aplica"
Assert ($cfgJson._fuentes.Count -ge 2) "_fuentes lista defaults + proyecto"

Write-Host "`n== 6. Initialize-Orquesta ==" -ForegroundColor Cyan
$initOut = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Initialize-Orquesta.ps1') -Objetivo 'Exportar cierres de caja a CSV' -Cwd $tmp
$planPath = Join-Path $tmp '.orquesta/PLAN.md'
Assert (Test-Path $planPath) "PLAN.md creado"
Assert ((Get-Content $planPath -Raw) -match 'estado: planificando') "PLAN arranca en planificando"
Assert ((Get-Content $planPath -Raw) -match 'orquesta:implementador \| claude \| opus') "tabla de enrutamiento refleja la config efectiva"
Assert (Test-Path (Join-Path $tmp '.orquesta/briefs')) "carpeta briefs creada"
Assert (Test-Path (Join-Path $tmp '.orquesta/.gitignore')) ".gitignore local creado"
$dup = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Initialize-Orquesta.ps1') -Objetivo 'otro' -Cwd $tmp
Assert ("$dup" -match 'ya existe') "no sobrescribe sin -Force"

Write-Host "`n== 7. Compuerta de delegación ==" -ForegroundColor Cyan
$base = @{ session_id = 'test-1'; cwd = $tmp; hook_event_name = 'PreToolUse'; tool_name = 'Agent'; permission_mode = 'auto' }
function Spawn([string]$type, [string]$prompt) { $i = $base.Clone(); $i.tool_input = @{ subagent_type = $type; prompt = $prompt; description = 'x'; model = 'sonnet' }; return $i }
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'Implementá .orquesta/briefs/BRIEF-01.md')
Assert ($r -match '"permissionDecision":"deny"' -and $r -match 'planificando') "PLAN en planificando → deny al implementador"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:cartografo' 'Mapeá el repo')
Assert ($r -eq '') "cartógrafo siempre pasa"
(Get-Content $planPath -Raw) -replace 'estado: planificando', 'estado: en-ejecucion' | Set-Content $planPath -Encoding UTF8
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'Implementá .orquesta/briefs/BRIEF-01.md, intento 1')
Assert ($r -match 'deny' -and $r -match 'no existe') "referencia a BRIEF-01 inexistente → deny"
New-BriefValido (Join-Path $tmp '.orquesta/briefs') '01'
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'Implementá .orquesta/briefs/BRIEF-01.md, intento 1')
Assert ($r -eq '') "en-ejecucion + BRIEF-01 válido → allow"
Set-Content (Join-Path $tmp '.orquesta/briefs/BRIEF-02.md') "# BRIEF-02`n## Archivos`n- NO tocar: nada`n## Criterios de aceptación`n1. que funcione bien`n## Cómo verificar`ncorrer los tests"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador-senior' 'Ejecutá BRIEF-02')
Assert ($r -match 'deny' -and $r -match 'Criterios de aceptaci' -and $r -match 'C.mo verificar') "BRIEF-02 sin criterios concretos ni comandos → deny explicando ambos"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' "Tarea inline. Criterios de aceptación:`n1. compila con dotnet build`n2. test X en verde")
Assert ($r -eq '') "brief inline con 2 criterios numerados → allow"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'Tarea inline con criterios de aceptación pero sin numerar nada')
Assert ($r -match 'deny' -and $r -match 'numerados') "brief inline sin criterios numerados → deny"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'Agregá un endpoint que exporte CSV, hacelo bien')
Assert ($r -match 'deny' -and $r -match 'BRIEF') "en-ejecucion sin BRIEF ni criterios → deny"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'general-purpose' ('x' * 2000))
Assert ($r -eq '') "prompt largo a general-purpose con PLAN en ejecución → allow"
$nested = Spawn 'orquesta:implementador' 'sin brief'; $nested.agent_id = 'abc'
$r = Invoke-Hook 'Gate-Delegacion.ps1' $nested
Assert ($r -eq '') "spawn anidado (agent_id) no se gobierna"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'sin brief') @{ ORQUESTA_GATES = '0' }
Assert ($r -eq '') "ORQUESTA_GATES=0 apaga la compuerta"
Remove-Item $planPath
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador-senior' 'Implementá BRIEF-02')
Assert ($r -match 'deny' -and $r -match 'Initialize-Orquesta') "sin PLAN → deny con instrucción de crear el plan"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'general-purpose' ('x' * 2000))
Assert ($r -match 'deny') "sin PLAN, prompt >= umbral a general-purpose → deny"
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'general-purpose' 'corto')
Assert ($r -eq '') "sin PLAN, prompt corto a general-purpose → allow"
Assert (Test-Path (Join-Path $tmp '.orquesta/bitacora.jsonl')) "los spawns quedan en la bitácora"

Write-Host "`n== 8. Compuerta de edición ==" -ForegroundColor Cyan
& $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Initialize-Orquesta.ps1') -Objetivo 'x' -Cwd $tmp -Force | Out-Null
(Get-Content $planPath -Raw) -replace 'estado: planificando', 'estado: en-ejecucion' | Set-Content $planPath -Encoding UTF8
function EditReq([string]$path) { return @{ session_id = 'test-1'; cwd = $tmp; hook_event_name = 'PreToolUse'; tool_name = 'Edit'; tool_input = @{ file_path = (Join-Path $tmp $path); old_string = 'a'; new_string = 'b' } } }
Assert ((Invoke-Hook 'Gate-Edicion.ps1' (EditReq 'src/Servicio.cs')) -match 'deny') "arquitecto edita src/*.cs en ejecución → deny"
Assert ((Invoke-Hook 'Gate-Edicion.ps1' (EditReq '.orquesta/PLAN.md')) -eq '') "editar PLAN.md → allow"
Assert ((Invoke-Hook 'Gate-Edicion.ps1' (EditReq '.orquesta/briefs/BRIEF-01.md')) -eq '') "editar brief → allow"
Assert ((Invoke-Hook 'Gate-Edicion.ps1' (EditReq 'docs/decisiones/ADR-x.md')) -eq '') "editar docs/ → allow"
Assert ((Invoke-Hook 'Gate-Edicion.ps1' (EditReq 'README.md')) -eq '') "editar .md → allow"
$w = EditReq 'src/Servicio.cs'; $w.agent_id = 'worker-1'
Assert ((Invoke-Hook 'Gate-Edicion.ps1' $w) -eq '') "un subagente sí puede editar código"
(Get-Content $planPath -Raw) -replace 'estado: en-ejecucion', 'estado: pausado' | Set-Content $planPath -Encoding UTF8
Assert ((Invoke-Hook 'Gate-Edicion.ps1' (EditReq 'src/Servicio.cs')) -eq '') "estado pausado relaja la compuerta"
(Get-Content $planPath -Raw) -replace 'estado: pausado', 'estado: en-ejecucion' | Set-Content $planPath -Encoding UTF8

Write-Host "`n== 9. Compuerta de cierre ==" -ForegroundColor Cyan
$stop = @{ session_id = 'sesion-42'; cwd = $tmp; hook_event_name = 'Stop'; stop_hook_active = $false; last_assistant_message = 'Listo.' }
$r = Invoke-Hook 'Gate-Cierre.ps1' $stop
Assert ($r -match '"decision":"block"' -and $r -match 'abierta') "PLAN en ejecución con tareas abiertas → block (1ª vez)"
$r = Invoke-Hook 'Gate-Cierre.ps1' $stop
Assert ($r -eq '') "misma sesión, 2ª vez → allow (una vez por sesión)"
$stop2 = $stop.Clone(); $stop2.session_id = 'sesion-43'; $stop2.stop_hook_active = $true
Assert ((Invoke-Hook 'Gate-Cierre.ps1' $stop2) -eq '') "stop_hook_active → allow (sin bucle)"
(Get-Content $planPath -Raw) -replace '- \[ \]', '- [x]' | Set-Content $planPath -Encoding UTF8
$stop3 = $stop.Clone(); $stop3.session_id = 'sesion-44'
Assert ((Invoke-Hook 'Gate-Cierre.ps1' $stop3) -eq '') "sin tareas abiertas → allow"

Write-Host "`n== 10. Bitácora de subagentes ==" -ForegroundColor Cyan
$sub = @{ session_id = 'test-1'; cwd = $tmp; hook_event_name = 'SubagentStop'; agent_type = 'orquesta:implementador'; agent_id = 'a1'; stop_hook_active = $false; last_assistant_message = "Estado: COMPLETADO`nCambios: x" }
Assert ((Invoke-Hook 'Log-Delegacion.ps1' $sub) -eq '') "reporte corto → sin nudge"
$largo = (1..90 | ForEach-Object { "línea $_" }) -join "`n"
$sub2 = $sub.Clone(); $sub2.last_assistant_message = $largo
$r = Invoke-Hook 'Log-Delegacion.ps1' $sub2
Assert ($r -match 'additionalContext' -and $r -match '90 líneas') "reporte de 90 líneas → nudge para resumir"
$bit = Get-Content (Join-Path $tmp '.orquesta/bitacora.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
Assert (@($bit | Where-Object { $_.evento -eq 'stop' }).Count -ge 2) "los stops quedan registrados"
Assert (@($bit | Where-Object { $_.PSObject.Properties['estado'] -and $_.estado -eq 'COMPLETADO' }).Count -ge 1) "detecta el estado COMPLETADO del reporte"

Write-Host "`n== 11. Show-Estado ==" -ForegroundColor Cyan
$estado = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Show-Estado.ps1') -Cwd $tmp | Out-String
Assert ($estado -match 'Enrutamiento efectivo') "imprime enrutamiento"
Assert ($estado -match 'orquesta:implementador \| claude \| opus') "refleja override del proyecto"
Assert ($estado -match 'estado: \*\*en-ejecucion\*\*') "refleja estado del PLAN"
Assert ($estado -match 'Bitácora de delegaciones') "resume la bitácora"
Assert ($estado -notmatch '\$\(' -and $estado -notmatch 'Get-Prop') "sin subexpresiones sin expandir (regresión backtick)"
Assert ($estado -match '`\.orquesta/PLAN\.md`') "la ruta del PLAN sale con formato de código Markdown"

Write-Host "`n== 12. Razones de deny sin caracteres de control ==" -ForegroundColor Cyan
Remove-Item $planPath -ErrorAction SilentlyContinue
& $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Initialize-Orquesta.ps1') -Objetivo 'x' -Cwd $tmp -Force | Out-Null
$r = Invoke-Hook 'Gate-Delegacion.ps1' (Spawn 'orquesta:implementador' 'sin brief')
Assert ($r -notmatch '\\u00[0-1][0-9a-f]' -and $r -match "'estado: planificando'") "deny de delegación sin ESC ni escapes raros"
Assert ($r -match "está en 'estado: planificando'") "la razón del deny llega con los acentos intactos (UTF-8 en stdout)"
(Get-Content $planPath -Raw) -replace 'estado: planificando', 'estado: en-ejecucion' | Set-Content $planPath -Encoding UTF8
$r = Invoke-Hook 'Gate-Edicion.ps1' (EditReq 'src/Servicio.cs')
Assert ($r -notmatch '\\u00[0-1][0-9a-f]') "deny de edición sin caracteres de control"
$r = Invoke-Hook 'Gate-Cierre.ps1' @{ session_id = 'sesion-99'; cwd = $tmp; hook_event_name = 'Stop'; stop_hook_active = $false }
Assert ($r -match '"decision":"block"' -and $r -notmatch '\\u00[0-1][0-9a-f]') "block de cierre sin caracteres de control"

Write-Host "`n== 13. Motor codex (Invoke-Codex con codex falso) ==" -ForegroundColor Cyan
$fake = Join-Path $PSScriptRoot 'fake-codex.ps1'
Set-Content (Join-Path $tmp '.claude/orquesta.json') ('{ "trabajadores": { "implementador": { "motor": "codex", "modelo": "gpt-fake-codex" } }, "motores": { "codex": { "comando": "' + ($fake -replace '\\', '/') + '", "modelo": "" } } }')
Remove-Item $planPath -ErrorAction SilentlyContinue
$estadoTxt = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Show-Estado.ps1') -Cwd $tmp | Out-String
Assert ($estadoTxt -match 'orquesta:implementador \| codex \| gpt-fake-codex') "Show-Estado muestra motor codex y su modelo"
Assert ($estadoTxt -match 'Motor codex: comando .* disponible') "Show-Estado detecta el comando codex"
Assert ($estadoTxt -match 'redefine motores\.codex\.comando') "Show-Estado avisa que el comando de Codex viene del .claude/orquesta.json del proyecto"
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador -Brief '.orquesta/briefs/BRIEF-07.md' -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 2 -and $r -match 'no existe') "sin PLAN → Invoke-Codex se niega (misma compuerta)"
& $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Initialize-Orquesta.ps1') -Objetivo 'codex' -Cwd $tmp -Force | Out-Null
(Get-Content $planPath -Raw) -replace 'estado: planificando', 'estado: en-ejecucion' | Set-Content $planPath -Encoding UTF8
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador -Brief '.orquesta/briefs/BRIEF-07.md' -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 2 -and $r -match 'no existe el BRIEF') "BRIEF inexistente → se niega"
Set-Content (Join-Path $tmp '.orquesta/briefs/BRIEF-07.md') "# BRIEF-07`n## Criterios de aceptación`n1. compila"
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador -Brief '.orquesta/briefs/BRIEF-07.md' -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 2 -and $r -match 'validaci.n de forma') "BRIEF con forma inválida → Invoke-Codex se niega"
New-BriefValido (Join-Path $tmp '.orquesta/briefs') '07'
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador -Brief '.orquesta/briefs/BRIEF-07.md' -Intento 1 -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "corrida codex exitosa (exit 0)"
Assert ($r -match 'rol=implementador' -and $r -match 'REPORTE-07' -and $r -match 'estado=COMPLETADO' -and $r -match 'tokens=1234/56') "cabecera con rol, brief, estado y tokens"
Assert ($r -match 'modelo=gpt-fake-codex') "usa el modelo configurado para el trabajador"
Assert ($r -match '\*\*Estado:\*\* COMPLETADO') "devuelve el REPORTE por stdout"
Assert (Test-Path (Join-Path $tmp '.orquesta/reportes/REPORTE-07-codex.md')) "REPORTE guardado en .orquesta/reportes"
$st = Get-Content (Join-Path $tmp '.orquesta/reportes/.codex-REPORTE-07.json') -Raw | ConvertFrom-Json
Assert ($st.thread_id -like 'thr_nuevo_*') "guarda el thread_id de Codex para reintentos"
$log = Get-Content (Join-Path $tmp '.orquesta/reportes/.codex-REPORTE-07.log') -Raw
Assert ($log -match 'contiene rol=True' -and $log -match 'contiene BRIEF=True') "el prompt lleva las instrucciones del rol y la ruta del BRIEF"
Assert ($log -match 'contiene task=True' -and $log -match 'contiene contrato=True') "el prompt tiene forma de bloques XML (<task>, contrato de salida)"
Assert ($log -match 'schema=reporte.schema.json') "pide salida estructurada con --output-schema reporte"
Assert (Test-Path (Join-Path $tmp '.orquesta/reportes/REPORTE-07-codex.json')) "el JSON crudo se guarda junto al reporte"
Assert ($r -match '2\. ✗ test en verde — sin evidencia' -and $r -match 'PROPUESTA: agregar caché') "el JSON se renderiza al formato REPORTE (✓/✗, propuestas)"
Assert ($r -match 'salida=json→markdown') "la cabecera indica salida estructurada"
$rv = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol revisor -Brief '.orquesta/briefs/BRIEF-07.md' -Insumo '.orquesta/reportes/REPORTE-07-codex.md' -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $rv -match 'estado=APROBADO' -and $rv -match '\*\*Dictamen:\*\* APROBADO') "rol revisor en codex → dictamen estructurado"
Assert ($rv -match '\[Sugerencia\] Nombre poco claro — `src/Fake.cs:10-12` \(confianza 0.6\)') "hallazgos con severidad, ubicación y confianza"
Assert ((Get-Content (Join-Path $tmp '.orquesta/reportes/.codex-REVISION-07.log') -Raw) -match 'schema=revision.schema.json') "el revisor usa el esquema de revisión"
Assert ($log -match '--sandbox workspace-write' -and $log -match '-m gpt-fake-codex' -and $log -match '--skip-git-repo-check') "flags de codex exec correctos (sandbox, modelo, sin git)"
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador -Brief '.orquesta/briefs/BRIEF-07.md' -Intento 2 -Hallazgos 'x.md' -Cwd $tmp 2>&1 | Out-String
Assert ($r -match 'intento=2 \(resume\)') "el reintento reanuda el hilo de Codex"
$log = Get-Content (Join-Path $tmp '.orquesta/reportes/.codex-REPORTE-07.log') -Raw
Assert ($log -match 'resume thr_nuevo_' -and $log -match 'REINTENTO-07-2') "resume <thread_id> con el prompt en archivo"
Assert ($log -match 'resume thr_nuevo_\S+ --json -o ') "en resume, --json/-o van después del subcomando (exec resume no acepta --sandbox ni -C)"
$rs = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador-senior -Brief '.orquesta/briefs/BRIEF-07.md' -Intento 2 -Hallazgos 'x.md' -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $rs -match 'rol=implementador-senior' -and $rs -match 'intento=2' -and $rs -notmatch '\(resume\)') "escalar a senior con -Intento 2 arranca un hilo limpio (sin resume)"
$st = Get-Content (Join-Path $tmp '.orquesta/reportes/.codex-REPORTE-07.json') -Raw | ConvertFrom-Json
Assert ($st.rol -eq 'implementador-senior' -and $st.thread_id -like 'thr_nuevo_*') "el estado guarda el rol y el hilo del último intento"
Set-Content (Join-Path $tmp '.orquesta/reportes/REPORTE-07-codex.md') 'VIEJO' -Encoding UTF8
$env:FAKE_CODEX_SIN_O = '1'
try { $r3 = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol implementador-senior -Brief '.orquesta/briefs/BRIEF-07.md' -Intento 3 -Hallazgos 'x.md' -Cwd $tmp 2>&1 | Out-String; $exit3 = $LASTEXITCODE }
finally { Remove-Item Env:FAKE_CODEX_SIN_O -ErrorAction SilentlyContinue }
Assert ($exit3 -eq 0 -and $r3 -match 'intento=3 \(resume\)' -and $r3 -match 'estado=COMPLETADO') "reintento del mismo rol reanuda el hilo"
$rep = Get-Content (Join-Path $tmp '.orquesta/reportes/REPORTE-07-codex.md') -Raw
Assert ($rep -notmatch 'VIEJO' -and $rep -match 'COMPLETADO') "si resume no reescribe -o, el REPORTE sale del JSONL y reemplaza al del intento anterior"
$bit = Get-Content (Join-Path $tmp '.orquesta/bitacora.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
Assert (@($bit | Where-Object { $_.PSObject.Properties['motor'] -and $_.motor -eq 'codex' -and $_.evento -eq 'stop' }).Count -ge 3) "bitácora registra los stops de codex con motor (implementador ×2 + revisor)"
Assert (@($bit | Where-Object { $_.PSObject.Properties['tokens_in'] -and $_.tokens_in -eq 1234 }).Count -ge 1) "bitácora registra tokens de codex"
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Invoke-Codex.ps1') -Rol cartografo -Tarea 'mapear' -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $r -match 'MAPA-') "roles de solo lectura corren sin PLAN ni BRIEF"

Write-Host "`n== 14. Hook SessionStart (aviso de PLAN abierto) ==" -ForegroundColor Cyan
$ss = @{ session_id = 's-1'; cwd = $tmp; hook_event_name = 'SessionStart'; source = 'startup' }
$r = Invoke-Hook 'Aviso-Sesion.ps1' $ss
Assert ($r -match '"additionalContext"' -and $r -match 'en-ejecucion' -and $r -match 'orquesta:arquitecto') "PLAN en ejecución → contexto para Claude con estado y cómo reanudar"
Assert ($r -match '"systemMessage"') "PLAN en ejecución → mensaje visible para el usuario"
(Get-Content $planPath -Raw) -replace 'estado: en-ejecucion', 'estado: cerrado' | Set-Content $planPath -Encoding UTF8
Assert ((Invoke-Hook 'Aviso-Sesion.ps1' $ss) -eq '') "PLAN cerrado → silencio"
Remove-Item $planPath
Assert ((Invoke-Hook 'Aviso-Sesion.ps1' $ss) -eq '') "sin PLAN → silencio"

Write-Host "`n== 15. Test-Brief.ps1 ==" -ForegroundColor Cyan
New-BriefValido (Join-Path $tmp '.orquesta/briefs') '09'
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Test-Brief.ps1') -Brief '.orquesta/briefs/BRIEF-09.md' -Cwd $tmp | Out-String
Assert ($LASTEXITCODE -eq 0 -and $r -match 'VÁLIDO') "BRIEF válido → exit 0"
Set-Content (Join-Path $tmp '.orquesta/briefs/BRIEF-10.md') (@('# BRIEF-NN — <título>', '## Criterios de aceptación', '1. …', '2. …', '## Cómo verificar', '```powershell', '```') -join "`n")
$r = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Test-Brief.ps1') -Brief '.orquesta/briefs/BRIEF-10.md' -Cwd $tmp | Out-String
Assert ($LASTEXITCODE -eq 2 -and $r -match 'INVÁLIDO' -and $r -match 'marcadores' -and $r -match 'NO tocar') "plantilla sin completar → exit 2 con los 4 problemas nombrados"

Write-Host "`n== 16. Doctor ==" -ForegroundColor Cyan
$doc = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Doctor-Orquesta.ps1') -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $doc -match 'Doctor orquesta') "doctor corre y devuelve Markdown"
Assert ($doc -match '✓ scripts completos' -and $doc -match 'hooks.json válido \(5 compuertas\)') "doctor valida scripts y hooks"
Assert ($doc -match 'motor codex' -and $doc -match 'Codex CLI') "doctor detecta que hay trabajadores en codex y lo verifica"
Assert ($doc -match '✗ el \.claude/orquesta\.json del proyecto redefine motores\.codex\.comando') "doctor avisa que el comando de Codex viene del .claude/orquesta.json del proyecto"
Assert ($doc -notmatch 'Exception') "doctor sin excepciones en la salida"

Write-Host "`n== 17. Trabajador extra en la config del proyecto (StrictMode) ==" -ForegroundColor Cyan
Set-Content (Join-Path $tmp '.claude/orquesta.json') '{ "trabajadores": { "qa": { "modelo": "haiku" } } }'
$ex = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Show-Estado.ps1') -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $ex -match 'orquesta:qa \| claude \| haiku \|' -and $ex -notmatch 'cannot be found') "Show-Estado tolera un trabajador sin esfuerzo/rol"
$ex = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Initialize-Orquesta.ps1') -Objetivo 'qa' -Cwd $tmp -Force 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and (Get-Content $planPath -Raw) -match 'orquesta:qa \| claude \| haiku \|') "Initialize-Orquesta incluye al trabajador extra en la tabla del PLAN"
$ex = & $pwsh -NoProfile -NonInteractive -File (Join-Path $Scripts 'Doctor-Orquesta.ps1') -Cwd $tmp 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $ex -notmatch 'cannot be found' -and $ex -match 'todos en Claude') "Doctor tolera el trabajador extra"

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`n== Resultado: $ok ok, $fallos fallos ==" -ForegroundColor $(if ($fallos) { 'Red' } else { 'Green' })
exit $(if ($fallos) { 1 } else { 0 })
