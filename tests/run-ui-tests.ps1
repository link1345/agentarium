param(
    [string]$GodotExecutable = 'Godot_v4.7-stable_win64_console.exe',
    [Parameter(Mandatory)][string]$GuaSource,
    [int]$Port = 18765
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
Set-Location $projectPath
$runPath = Join-Path $projectPath ('artifacts\ui-runs\' + [guid]::NewGuid().ToString('N'))
$env:APPDATA = Join-Path $runPath 'roaming'
$env:LOCALAPPDATA = Join-Path $runPath 'local'
$env:AGENTARIUM_DATA_DIR = Join-Path $runPath 'data'
$env:AGENTARIUM_DISABLE_SYNC = '1'
$env:GUA_SOURCE = $GuaSource
$env:GUA_BRIDGE_PORT = "$Port"
$env:GUA_BRIDGE_URL = "ws://127.0.0.1:$Port"
$process = Start-Process -FilePath $GodotExecutable -ArgumentList @('--path',('"'+$projectPath+'"'),'--','--theater') -PassThru -WindowStyle Hidden
try {
    $ready = $false
    for ($i=0;$i -lt 30;$i++) {
        & bun tests/gua-driver.ts tree *> $null
        if ($LASTEXITCODE -eq 0) { $ready=$true;break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Gua bridge did not become ready' }
    & bun tests/gua-driver.ts suite
    if ($LASTEXITCODE -ne 0) { throw 'Gua UI test failed' }
} finally {
    & bun tests/gua-driver.ts click quit
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Gua could not close the test host; close its window manually.' }
}
