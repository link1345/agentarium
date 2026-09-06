param(
    [string]$GodotExecutable = 'Godot_v4.7-stable_win64_console.exe',
    [switch]$Theater,
    [switch]$Gua,
    [int]$GuaPort = 18765,
    [string]$DataDir
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if ($DataDir) { $env:AGENTARIUM_DATA_DIR = [IO.Path]::GetFullPath($DataDir) }
if ($Gua) { $env:GUA_BRIDGE_PORT = "$GuaPort" } else { Remove-Item Env:\GUA_BRIDGE_PORT -ErrorAction SilentlyContinue }
$mode = if ($Theater) { '--theater' } else { '--mascot' }
& $GodotExecutable --path $projectPath -- $mode
exit $LASTEXITCODE
