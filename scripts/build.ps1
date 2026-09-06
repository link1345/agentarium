param([string]$GodotExecutable = 'Godot_v4.7-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $projectPath 'artifacts\build-runtime'
$env:LOCALAPPDATA = Join-Path $projectPath 'artifacts\build-local'
New-Item -ItemType Directory -Force (Join-Path $projectPath 'dist') | Out-Null
$importOutput = & $GodotExecutable --headless --path $projectPath --editor --import --quit 2>&1
$importCode = $LASTEXITCODE
$importOutput | Write-Output
if ($importCode -ne 0 -or ($importOutput -join "`n") -match 'SCRIPT ERROR|Parse Error|Failed to load script') { throw 'Godot import failed' }
$exportStarted = [DateTime]::UtcNow
$exportOutput = & $GodotExecutable --headless --path $projectPath --export-release 'Windows Desktop' 2>&1
$exportCode = $LASTEXITCODE
$exportOutput | Write-Output
$outputPath = Join-Path $projectPath 'dist\Agentarium.exe'
if ($exportCode -ne 0 -or ($exportOutput -join "`n") -match 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to export' -or -not (Test-Path $outputPath)) { throw 'Godot export failed' }
if ((Get-Item $outputPath).LastWriteTimeUtc -lt $exportStarted) { throw 'Export did not replace the previous executable' }
$runtimeSource = Join-Path $projectPath 'runtime'
if (-not (Test-Path (Join-Path $runtimeSource 'python\pythonw.exe'))) { throw 'Run scripts/prepare-runtime.py with a Python runtime before packaging.' }
Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $projectPath 'dist') -Recurse -Force
New-Item -ItemType Directory -Force (Join-Path $projectPath 'dist\scripts') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'desktop_sync.py') -Destination (Join-Path $projectPath 'dist\scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'rollout_state.py') -Destination (Join-Path $projectPath 'dist\scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'github_sync.py') -Destination (Join-Path $projectPath 'dist\scripts') -Force
foreach ($name in @('README.md','THIRD_PARTY_NOTICES.md','LICENSE')) { Copy-Item -LiteralPath (Join-Path $projectPath $name) -Destination (Join-Path $projectPath 'dist') -Force }
Copy-Item -LiteralPath (Join-Path $projectPath 'docs') -Destination (Join-Path $projectPath 'dist') -Recurse -Force
Write-Output (Join-Path $projectPath 'dist\Agentarium.exe')
