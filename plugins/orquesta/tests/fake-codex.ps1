# codex falso para pruebas: imita `codex exec --json ... -o <archivo> [-]` y `... resume <thread> "<prompt>"`.
# Escribe un REPORTE en el archivo -o, emite eventos JSONL por stdout y ruido por stderr, como el real.
$argv = $args
$out = $null; $schema = $null; $resume = $false; $thread = 'thr_nuevo_' + [Guid]::NewGuid().ToString('N').Substring(0, 6); $leerStdin = $false
for ($i = 0; $i -lt $argv.Count; $i++) {
    switch ($argv[$i]) {
        '-o'     { $out = $argv[$i + 1]; $i++ }
        '--output-schema' { $schema = $argv[$i + 1]; $i++ }
        'resume' { $resume = $true; $thread = $argv[$i + 1]; $i++ }
        '-'      { $leerStdin = $true }
    }
}
$prompt = if ($leerStdin) { [Console]::In.ReadToEnd() } else { ($argv | Select-Object -Last 1) }
[Console]::Error.WriteLine("fake-codex: argumentos: $($argv -join ' ')")
[Console]::Error.WriteLine("fake-codex: prompt de $($prompt.Length) chars; contiene rol=$($prompt -match '<role_instructions>'); contiene BRIEF=$($prompt -match 'BRIEF-'); contiene task=$($prompt -match '<task>'); contiene contrato=$($prompt -match '<structured_output_contract>|<compact_output_contract>'); schema=$(if ($schema) { Split-Path $schema -Leaf } else { 'ninguno' })")

$estado = if ($resume) { 'COMPLETADO' } elseif ($prompt -match 'FORZAR_BLOQUEO') { 'BLOQUEADO' } else { 'COMPLETADO' }
if ($schema -and $schema -like '*revision*') {
    $reporte = @{ dictamen = 'APROBADO'; resumen = 'fake: todo verificado'; criterios = @(@{ numero = 1; texto = 'compila'; cumplido = $true; evidencia = 'dotnet build ok' })
        hallazgos = @(@{ severidad = 'sugerencia'; titulo = 'Nombre poco claro'; detalle = 'fake'; archivo = 'src/Fake.cs'; linea_inicio = 10; linea_fin = 12; confianza = 0.6; recomendacion = 'renombrar' })
        comandos = @(@{ comando = 'dotnet test'; resultado = '3 pasaron' }); para_arquitecto = @('ratificar el nombre del DTO') } | ConvertTo-Json -Depth 5
} elseif ($schema) {
    $reporte = @{ estado = $estado; resumen = 'fake: implementado'; cambios = @(@{ archivo = 'src/Fake.cs'; descripcion = 'generado por fake-codex' })
        criterios = @(@{ numero = 1; texto = 'compila'; cumplido = $true; evidencia = 'src/Fake.cs:1' }, @{ numero = 2; texto = 'test en verde'; cumplido = $false; evidencia = '' })
        pruebas = @(@{ comando = 'dotnet test'; resultado = '2 pasaron, 1 falló' }); dudas = @(); propuestas = @('agregar caché'); bloqueo = $(if ($estado -eq 'BLOQUEADO') { '¿qué tabla?' } else { '' }) } | ConvertTo-Json -Depth 5
} else {
    $reporte = @"
# REPORTE — fake ($(if ($resume) { 'resume' } else { 'nuevo' }))

**Estado:** $estado

## Cambios
- src/Fake.cs — generado por fake-codex

## Criterios de aceptación
1. ✓ compila — evidencia: fake

## Pruebas ejecutadas
- ninguna (fake)
"@
}
if ($out) { Set-Content -LiteralPath $out -Value $reporte -Encoding UTF8 }

Write-Output ('{"type":"thread.started","thread_id":"' + $thread + '"}')
Write-Output '{"type":"turn.started"}'
Write-Output ('{"type":"item.completed","item":{"type":"agent_message","text":' + ($reporte | ConvertTo-Json) + '}}')
Write-Output '{"type":"turn.completed","usage":{"input_tokens":1234,"output_tokens":56}}'
exit 0
