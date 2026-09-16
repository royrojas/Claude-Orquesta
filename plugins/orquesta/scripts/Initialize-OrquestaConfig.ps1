<#
.SYNOPSIS
  Crea .claude/orquesta.json en el proyecto si no existe: un esqueleto mínimo y editable, con un `_doc` por bloque,
  solo para lo que se suele cambiar (trabajadores, motores.codex, contexto.obsidian). Vacío de overrides se comporta
  igual que los defaults del plugin y sigue al día cuando el plugin cambia — por eso NO se vuelcan los defaults.
  Si el CLAUDE.md del proyecto tiene la sección "Memoria del proyecto (Obsidian)" con una línea
  "- Decisiones: `<ruta absoluta>`", la pre-llena en carpeta_decisiones y carpeta_handoffs (los HANDOFF van a la
  misma carpeta; se distinguen por prefijo). Nunca sobreescribe: si el archivo ya existe, lo dice y sale con 0.
.EXAMPLE
  pwsh -NoProfile -File scripts/Initialize-OrquestaConfig.ps1
#>
param([string]$Cwd = (Get-Location).Path)
. "$PSScriptRoot/OrquestaCommon.ps1"

$dir  = Join-Path $Cwd '.claude'
$ruta = Join-Path $dir 'orquesta.json'
if (Test-Path -LiteralPath $ruta) {
    Write-Output "orquesta: ya existe $ruta y no se toca. Editalo a mano; verificá el resultado con /orquesta:estado."
    exit 0
}

$decisiones = Get-ObsidianCarpetaDesdeClaudeMd -Cwd $Cwd

$obsidian = [ordered]@{
    _doc = 'carpeta_decisiones y carpeta_handoffs: ruta absoluta, o relativa al repo, o relativa a contexto.obsidian.vault_root (ese va en ~/.claude/orquesta.json, personal). usar=false apaga ADR y HANDOFF por completo. Si esta seccion solo tiene _doc, se usan los defaults del plugin (docs/decisiones dentro del repo).'
}
if ($decisiones) {
    $obsidian['carpeta_decisiones'] = $decisiones
    $obsidian['carpeta_handoffs']   = $decisiones
}

$cfg = [ordered]@{
    _doc = 'Config de orquesta para ESTE proyecto. Solo lo que difiere de los defaults del plugin (config/orquesta.defaults.json): lo que no este aca usa el default y sigue al dia cuando el plugin cambia. Las claves _doc son comentarios, se ignoran. Verifica el resultado con /orquesta:estado, que dice de que archivo sale cada valor.'
    trabajadores = [ordered]@{
        _doc = 'Por rol: { "motor": "claude" o "codex", "modelo": "haiku" | "sonnet" | "opus" | "fable" | "inherit" (claude) o un modelo de Codex como "gpt-5.6-terra" (codex) }. Roles: cartografo, implementador, implementador-senior, revisor, auditor-seguridad, documentador. Ejemplo: "implementador": { "motor": "codex", "modelo": "gpt-5.6-terra" }. Quien implementa y quien revisa deberian ser modelos o proveedores distintos.'
    }
    motores = [ordered]@{
        codex = [ordered]@{
            _doc = 'razonamiento: low | medium | high | xhigh (una sola perilla para TODOS los trabajadores en codex; el modelo si es por rol). sandbox: workspace-write (default) o danger-full-access (en Windows, corriendo dentro de Claude Code, suele hacer falta este ultimo; ver README seccion 16).'
        }
    }
    contexto = [ordered]@{ obsidian = $obsidian }
}

New-Item -ItemType Directory -Path $dir -Force | Out-Null
Set-Content -LiteralPath $ruta -Value ($cfg | ConvertTo-Json -Depth 6) -Encoding UTF8

Write-Output "orquesta: config del proyecto creada en $ruta"
if ($decisiones) { Write-Output "Obsidian: carpeta_decisiones y carpeta_handoffs pre-llenadas desde CLAUDE.md -> $decisiones" }
else { Write-Output "Obsidian: no encontre una linea '- Decisiones: <ruta absoluta>' en CLAUDE.md; se usan los defaults (docs/decisiones dentro del repo). Agrega carpeta_decisiones/carpeta_handoffs a mano si queres otra carpeta." }
Write-Output "El resto del archivo son solo _doc: cualquier clave que agregues pisa el default correspondiente. Verifica con /orquesta:estado."
