# OrquestaCommon.ps1 — funciones compartidas por los scripts del plugin.
# Se carga con: . "$PSScriptRoot/OrquestaCommon.ps1"
# Requiere PowerShell 7+. Sin dependencias externas.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Claude Code manda y lee UTF-8; sin esto, en Windows la consola impone su code page y los acentos de los
# JSON de entrada/salida se corrompen (también al correr la suite desde Git Bash). Falla en silencio si no hay consola.
try {
    $utf8 = [Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
} catch { }

function Get-OrquestaPluginRoot {
    # scripts/ está un nivel bajo la raíz del plugin.
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Merge-OrquestaObject {
    <#
      Merge profundo de dos objetos PSCustomObject (resultado de ConvertFrom-Json).
      Las propiedades de $Override reemplazan a las de $Base; los objetos anidados se mezclan.
      Los arrays se reemplazan completos (no se concatenan).
    #>
    param($Base, $Override)

    if ($null -eq $Override) { return $Base }
    if ($null -eq $Base) { return $Override }
    if (-not ($Base -is [pscustomobject]) -or -not ($Override -is [pscustomobject])) { return $Override }

    $result = [ordered]@{}
    foreach ($p in $Base.PSObject.Properties) { $result[$p.Name] = $p.Value }
    foreach ($p in $Override.PSObject.Properties) {
        if ($result.Contains($p.Name) -and ($result[$p.Name] -is [pscustomobject]) -and ($p.Value -is [pscustomobject])) {
            $result[$p.Name] = Merge-OrquestaObject -Base $result[$p.Name] -Override $p.Value
        } else {
            $result[$p.Name] = $p.Value
        }
    }
    return [pscustomobject]$result
}

function Read-OrquestaJsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Warning "orquesta: no se pudo leer JSON en $Path : $($_.Exception.Message)"
        return $null
    }
}

function Get-OrquestaConfig {
    <#
      Config efectiva = defaults del plugin <- ~/.claude/orquesta.json <- <cwd>/.claude/orquesta.json
      Devuelve un PSCustomObject con una propiedad extra `_fuentes` (rutas que aportaron).
    #>
    param([string]$Cwd = (Get-Location).Path)

    $root = Get-OrquestaPluginRoot
    $defaultsPath = Join-Path $root 'config/orquesta.defaults.json'
    $cfg = Read-OrquestaJsonFile -Path $defaultsPath
    if ($null -eq $cfg) { throw "orquesta: falta config/orquesta.defaults.json en $root" }

    $fuentes = @($defaultsPath)

    $home_ = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
    $userPath = Join-Path $home_ '.claude/orquesta.json'
    $userCfg = Read-OrquestaJsonFile -Path $userPath
    if ($null -ne $userCfg) { $cfg = Merge-OrquestaObject -Base $cfg -Override $userCfg; $fuentes += $userPath }

    if ($Cwd) {
        $projPath = Join-Path $Cwd '.claude/orquesta.json'
        $projCfg = Read-OrquestaJsonFile -Path $projPath
        if ($null -ne $projCfg) { $cfg = Merge-OrquestaObject -Base $cfg -Override $projCfg; $fuentes += $projPath }
    }

    $cfg | Add-Member -NotePropertyName '_fuentes' -NotePropertyValue $fuentes -Force
    return $cfg
}

function Test-OrquestaGatesEnabled {
    # ORQUESTA_GATES=0 apaga todas las compuertas de la sesión.
    return -not ($env:ORQUESTA_GATES -eq '0')
}

function Read-HookInput {
    # Lee el JSON que Claude Code manda por stdin. Devuelve $null si no hay nada o no parsea.
    try {
        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-HookJson {
    param([Parameter(Mandatory)]$Object)
    # Salida compacta en una sola línea: Claude Code parsea stdout como JSON solo si empieza con { y termina con }.
    [Console]::Out.Write(($Object | ConvertTo-Json -Depth 10 -Compress))
}

function Deny-ToolUse {
    param([Parameter(Mandatory)][string]$Reason)
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $Reason
        }
    }
    exit 0
}

function Add-ToolContext {
    param([Parameter(Mandatory)][string]$Event, [Parameter(Mandatory)][string]$Context)
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName     = $Event
            additionalContext = $Context
        }
    }
}

function Get-Prop {
    # Acceso seguro a propiedades anidadas: Get-Prop $obj 'tool_input.prompt'
    param($Object, [string]$Path)
    $cur = $Object
    foreach ($seg in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        $prop = $cur.PSObject.Properties[$seg]
        if ($null -eq $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

function Get-TrabajadorInfo {
    <#
      Motor y modelo efectivos de un trabajador según la config. Tolera entradas incompletas (un trabajador agregado
      en .claude/orquesta.json sin esfuerzo/rol) y resuelve el modelo de codex: un alias de Claude o vacío cae a
      motores.codex.modelo, y si ese también está vacío, 'codex-default'.
    #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Nombre)
    $t = Get-Prop $Config "trabajadores.$Nombre"
    $motor = "$(Get-Prop $t 'motor')"; if (-not $motor) { $motor = 'claude' }
    $modelo = "$(Get-Prop $t 'modelo')"
    if ($motor -eq 'codex' -and $modelo -in @('haiku', 'sonnet', 'opus', 'fable', 'inherit', '')) {
        $modelo = "$(Get-Prop $Config 'motores.codex.modelo')"; if (-not $modelo) { $modelo = 'codex-default' }
    }
    return [pscustomobject]@{ Nombre = $Nombre; Motor = $motor; Modelo = $modelo; Esfuerzo = "$(Get-Prop $t 'esfuerzo')"; Rol = "$(Get-Prop $t 'rol')" }
}

function Get-OverridesRiesgosos {
    <#
      Claves de motores.codex que, definidas en el .claude/orquesta.json DEL PROYECTO (viaja con el repo), permiten que un
      repo clonado decida qué ejecutable corre el arquitecto o lo saque del sandbox. Devuelve descripciones; vacío si no hay.
    #>
    param([string]$Cwd)
    $r = @()
    $proj = Read-OrquestaJsonFile -Path (Join-Path $Cwd '.claude/orquesta.json')
    if ($null -eq $proj) { return $r }
    foreach ($k in @('comando', 'args_extra')) {
        $v = Get-Prop $proj "motores.codex.$k"
        if ($null -ne $v -and "$(@($v) -join ' ')" -ne '') { $r += "motores.codex.$k = $(@($v) -join ' ')" }
    }
    if ("$(Get-Prop $proj 'motores.codex.sandbox')" -eq 'danger-full-access') { $r += 'motores.codex.sandbox = danger-full-access' }
    return $r
}

function Get-PlanInfo {
    <#
      Parsea .orquesta/PLAN.md (ruta según config).
      Devuelve: Existe, Ruta, Estado, Objetivo, Abiertos, Cerrados, Diferidos, VerificacionCerrada, ItemsAbiertos (títulos)
    #>
    param([string]$Cwd = (Get-Location).Path, $Config)

    if ($null -eq $Config) { $Config = Get-OrquestaConfig -Cwd $Cwd }
    $planRel = Get-Prop $Config 'rutas.plan'
    if (-not $planRel) { $planRel = '.orquesta/PLAN.md' }
    $planPath = Join-Path $Cwd $planRel

    $info = [ordered]@{
        Existe = $false; Ruta = $planPath; Estado = $null; Objetivo = $null
        Abiertos = 0; Cerrados = 0; Diferidos = 0; VerificacionCerrada = $false
        ItemsAbiertos = @()
    }
    if (-not (Test-Path -LiteralPath $planPath)) { return [pscustomobject]$info }

    $info.Existe = $true
    $lines = Get-Content -LiteralPath $planPath -Encoding UTF8

    # Frontmatter YAML simple (clave: valor) al inicio del archivo.
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if ($l.Trim() -eq '---') { break }
            if ($l -match '^\s*estado\s*:\s*(.+?)\s*$')   { $info.Estado   = $Matches[1].Trim().Trim('"').Trim("'").ToLower() }
            if ($l -match '^\s*objetivo\s*:\s*(.+?)\s*$') { $info.Objetivo = $Matches[1].Trim().Trim('"').Trim("'") }
        }
    }

    # Ítems de tarea: "- [ ] 3. Título", "- [x] ...", "- [~] ..." (solo dentro de ## Tareas hasta el próximo ##)
    $enTareas = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*##\s+') { $enTareas = ($l -match '^\s*##\s+Tareas'); continue }
        if (-not $enTareas) { continue }
        if ($l -match '^\s*-\s*\[( |x|X|~)\]\s*(.*)$') {
            $mark = $Matches[1]; $title = $Matches[2].Trim()
            switch ($mark) {
                ' ' { $info.Abiertos++; $info.ItemsAbiertos += $title }
                '~' { $info.Diferidos++ }
                default {
                    $info.Cerrados++
                    if ($title -match '^V\.\s') { $info.VerificacionCerrada = $true }
                }
            }
        }
    }
    return [pscustomobject]$info
}

function Get-RelativePathSafe {
    # Ruta relativa normalizada con '/' respecto a $Base; si no está bajo $Base devuelve la absoluta normalizada.
    param([string]$Path, [string]$Base)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $full = $Path
    try { if (-not [IO.Path]::IsPathRooted($full)) { $full = Join-Path $Base $full } } catch { }
    $full = $full -replace '\\', '/'
    $baseN = ($Base -replace '\\', '/').TrimEnd('/')
    if ($full.StartsWith($baseN + '/', [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($baseN.Length + 1)
    }
    return $full
}

function Add-BitacoraEntry {
    param([string]$Cwd, $Config, [hashtable]$Entry)
    if (-not (Get-Prop $Config 'compuertas.bitacora')) { return }
    $raiz = Join-Path $Cwd (Get-Prop $Config 'rutas.raiz')
    if (-not (Test-Path -LiteralPath $raiz)) { return }   # solo en proyectos donde orquesta está activo
    $ruta = Join-Path $Cwd (Get-Prop $Config 'rutas.bitacora')
    $Entry['ts'] = (Get-Date).ToString('o')
    try {
        Add-Content -LiteralPath $ruta -Value ($Entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
    } catch { }
}

function Test-BriefShape {
    <#
      Valida la FORMA de un BRIEF (no su calidad): que tenga lo mínimo para que un trabajador lo ejecute sin preguntar
      y un revisor pueda aprobarlo sin interpretar.
        - ## Criterios de aceptación con >= 2 ítems numerados concretos
        - ## Cómo verificar con al menos un comando dentro de un bloque de código
        - una línea "NO tocar:" (aunque diga "nada")
        - sin marcadores de la plantilla (BRIEF-NN, <título>)
      Devuelve: Valido, Problemas (lista), Criterios, Comandos
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Valido = $false; Problemas = @("no existe el archivo $Path"); Criterios = 0; Comandos = 0 }
    }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $seccion = ''; $criterios = 0; $comandos = 0; $enFence = $false; $noTocar = $false
    foreach ($l in $lines) {
        if (-not $enFence -and $l -match '^\s*##\s+(.+?)\s*$') { $seccion = $Matches[1]; continue }
        if ($l -match '^\s*```') { $enFence = -not $enFence; continue }
        if ($l -match '(?i)\bno tocar\b') { $noTocar = $true }
        if ($seccion -match '(?i)^criterios de aceptaci') {
            if ($l -match '^\s*\d+\.\s+(.+)$') {
                $t = $Matches[1].Trim()
                if ($t.Length -ge 8 -and $t -notmatch '^[….\s]+$') { $criterios++ }
            }
        } elseif ($seccion -match '(?i)^c[oó]mo verificar') {
            if ($enFence -and -not [string]::IsNullOrWhiteSpace($l) -and $l.Trim() -notmatch '^#') { $comandos++ }
        }
    }
    $problemas = @()
    if ($criterios -lt 2) { $problemas += "'## Criterios de aceptación' necesita al menos 2 ítems numerados y concretos (hay $criterios)" }
    if ($comandos -lt 1)  { $problemas += "'## Cómo verificar' necesita al menos un comando dentro de un bloque de código" }
    if (-not $noTocar)    { $problemas += "falta la línea 'NO tocar:' en ## Archivos (puede ser 'NO tocar: nada')" }
    $todo = ($lines -join "`n")
    if ($todo -match 'BRIEF-NN|<t[ií]tulo>') { $problemas += "quedan marcadores de la plantilla (BRIEF-NN, <título>)" }
    return [pscustomobject]@{ Valido = ($problemas.Count -eq 0); Problemas = $problemas; Criterios = $criterios; Comandos = $comandos }
}

function ConvertTo-ReporteMarkdown {
    # Renderiza el JSON estructurado de un trabajador al formato REPORTE que leen el arquitecto y el revisor.
    param([Parameter(Mandatory)]$Json, [string]$Titulo = 'REPORTE', [int]$Intento = 1)
    $o = New-Object System.Collections.Generic.List[string]
    $o.Add("# $Titulo (intento $Intento)"); $o.Add('')
    $o.Add("**Estado:** $(Get-Prop $Json 'estado')")
    $res = Get-Prop $Json 'resumen'; if ($res) { $o.Add(''); $o.Add("$res") }
    $o.Add(''); $o.Add('## Cambios')
    $cambios = @(Get-Prop $Json 'cambios')
    if ($cambios.Count -eq 0) { $o.Add('- (ninguno)') } else { foreach ($c in $cambios) { $o.Add("- ``$(Get-Prop $c 'archivo')`` — $(Get-Prop $c 'descripcion')") } }
    $o.Add(''); $o.Add('## Criterios de aceptación')
    foreach ($c in @(Get-Prop $Json 'criterios')) {
        $mark = if ((Get-Prop $c 'cumplido') -eq $true) { '✓' } else { '✗' }
        $ev = Get-Prop $c 'evidencia'; $evTxt = if ($ev) { " — evidencia: $ev" } else { ' — sin evidencia' }
        $o.Add("$(Get-Prop $c 'numero'). $mark $(Get-Prop $c 'texto')$evTxt")
    }
    $o.Add(''); $o.Add('## Pruebas ejecutadas')
    $pruebas = @(Get-Prop $Json 'pruebas')
    if ($pruebas.Count -eq 0) { $o.Add('- (ninguna)') } else { foreach ($p in $pruebas) { $o.Add("- ``$(Get-Prop $p 'comando')`` → $(Get-Prop $p 'resultado')") } }
    $dudas = @(Get-Prop $Json 'dudas'); $bloqueo = Get-Prop $Json 'bloqueo'
    if ($dudas.Count -gt 0 -or $bloqueo) {
        $o.Add(''); $o.Add('## Dudas / riesgos / bloqueo')
        if ($bloqueo) { $o.Add("- **BLOQUEADO:** $bloqueo") }
        foreach ($d in $dudas) { $o.Add("- $d") }
    }
    $props = @(Get-Prop $Json 'propuestas')
    if ($props.Count -gt 0) { $o.Add(''); $o.Add('## Propuestas (no aplicadas)'); foreach ($p in $props) { $o.Add("- PROPUESTA: $p") } }
    return ($o -join "`n")
}

function ConvertTo-RevisionMarkdown {
    # Renderiza el JSON estructurado de revisor/auditor al formato de dictamen.
    param([Parameter(Mandatory)]$Json, [string]$Titulo = 'REVISIÓN', [int]$Intento = 1)
    $o = New-Object System.Collections.Generic.List[string]
    $o.Add("## $Titulo (intento $Intento)")
    $o.Add("**Dictamen:** $(Get-Prop $Json 'dictamen')")
    $res = Get-Prop $Json 'resumen'; if ($res) { $o.Add("$res") }
    $o.Add(''); $o.Add('### Criterios')
    foreach ($c in @(Get-Prop $Json 'criterios')) {
        $mark = if ((Get-Prop $c 'cumplido') -eq $true) { '✓' } else { '✗' }
        $o.Add("$(Get-Prop $c 'numero'). $mark $(Get-Prop $c 'texto') — evidencia: $(Get-Prop $c 'evidencia')")
    }
    $o.Add(''); $o.Add('### Hallazgos')
    $h = @(Get-Prop $Json 'hallazgos')
    if ($h.Count -eq 0) { $o.Add('- (sin hallazgos)') }
    foreach ($x in $h) {
        $sev = switch ("$(Get-Prop $x 'severidad')") { 'critico' { 'Crítico' } 'debe' { 'Debe' } default { 'Sugerencia' } }
        $ubic = "$(Get-Prop $x 'archivo')"; $li = Get-Prop $x 'linea_inicio'; $lf = Get-Prop $x 'linea_fin'
        if ($li) { $ubic += ":$li"; if ($lf -and $lf -ne $li) { $ubic += "-$lf" } }
        $conf = Get-Prop $x 'confianza'; $confTxt = if ($null -ne $conf) { " (confianza $([math]::Round([double]$conf, 2)))" } else { '' }
        $o.Add("- [$sev] $(Get-Prop $x 'titulo') — ``$ubic``$confTxt. $(Get-Prop $x 'detalle') → $(Get-Prop $x 'recomendacion')")
    }
    $o.Add(''); $o.Add('### Comandos ejecutados')
    $cmds = @(Get-Prop $Json 'comandos')
    if ($cmds.Count -eq 0) { $o.Add('- (ninguno)') } else { foreach ($c in $cmds) { $o.Add("- ``$(Get-Prop $c 'comando')`` → $(Get-Prop $c 'resultado')") } }
    $pa = @(Get-Prop $Json 'para_arquitecto')
    if ($pa.Count -gt 0) { $o.Add(''); $o.Add('### Para el arquitecto'); foreach ($p in $pa) { $o.Add("- $p") } }
    return ($o -join "`n")
}
