param([string]$GuaArchive, [string]$GodotTemplatesArchive)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$cachePath = Join-Path $projectPath 'artifacts\downloads'
New-Item -ItemType Directory -Force $cachePath | Out-Null
function Get-VerifiedArchive([string]$Supplied, [string]$Name, [string]$Url, [string]$Hash) {
    $archivePath = if ($Supplied) { [IO.Path]::GetFullPath($Supplied) } else { Join-Path $cachePath $Name }
    if (-not (Test-Path -LiteralPath $archivePath)) {
        if ($Supplied) { throw "Archive not found: $archivePath" }
        Invoke-WebRequest -Uri $Url -OutFile $archivePath
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Hash) { throw "Checksum mismatch: $Name" }
    return $archivePath
}
$guaZip = Get-VerifiedArchive $GuaArchive 'gua-godot-addon-v1.0.10.zip' 'https://github.com/link1345/gua/releases/download/gua-v1.0.10/gua-godot-addon-v1.0.10.zip' '8549c2dff5906981b4efedecb6a09316d05943e58f8fb2c12e607501a2900ec7'
$templatesZip = Get-VerifiedArchive $GodotTemplatesArchive 'Godot_v4.7-stable_export_templates.tpz' 'https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz' '9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec'
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Copy-ZipEntry([string]$Zip, [string]$Entry, [string]$Target) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $item = $archive.GetEntry($Entry)
        if ($null -eq $item) { throw "Missing archive entry: $Entry" }
        New-Item -ItemType Directory -Force (Split-Path -Parent $Target) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($item, $Target, $true)
    } finally { $archive.Dispose() }
}
foreach ($file in @('gua_auto_adapter.gd','gua.gdextension','bin/gua_godot.windows.debug.x86_64.dll','bin/gua_godot.windows.release.x86_64.dll')) {
    Copy-ZipEntry $guaZip "addons/gua/$file" (Join-Path $projectPath "addons/gua/$file")
}
foreach ($file in @('windows_debug_x86_64.exe','windows_release_x86_64.exe')) {
    Copy-ZipEntry $templatesZip "templates/$file" (Join-Path $projectPath "artifacts/templates/$file")
}
Set-Content (Join-Path $projectPath 'addons/gua/.gua-version') '1.0.10' -NoNewline
Write-Output 'Gua 1.0.10 + Godot 4.7 Windows templates ready.'
