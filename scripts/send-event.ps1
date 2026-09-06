param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][ValidateSet('task.started','task.progress','tool.started','tool.completed','input.required','ci.failed','task.failed','review.received','task.completed','task.paused','task.resumed','user.acknowledged')][string]$Type,
    [string]$Title,
    [string]$Summary,
    [ValidateSet('fox','dog','bird','cat')][string]$Pet,
    [string]$Url,
    [long]$Sequence = -1,
    [string]$EventId = [guid]::NewGuid().ToString(),
    [string]$DataDir = $(if ($env:AGENTARIUM_DATA_DIR) { $env:AGENTARIUM_DATA_DIR } else { Join-Path $env:APPDATA 'Godot\app_userdata\Agentarium' })
)
$ErrorActionPreference = 'Stop'
$eventData = @{ id = $EventId; task_id = $TaskId; type = $Type }
foreach ($field in @('Title','Summary','Pet','Url')) {
    if ($PSBoundParameters.ContainsKey($field)) { $eventData[$field.ToLowerInvariant()] = $PSBoundParameters[$field] }
}
if ($Sequence -ge 0) { $eventData.sequence = $Sequence }
$inboxPath = Join-Path $DataDir 'inbox'
New-Item -ItemType Directory -Force -Path $inboxPath | Out-Null
$fileId = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfffffff'), [guid]::NewGuid().ToString('N')
$tempPath = Join-Path $inboxPath ($fileId + '.tmp')
$finalPath = Join-Path $inboxPath ($fileId + '.json')
$json = $eventData | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 16384) { throw 'Event exceeds 16 KiB.' }
[IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $tempPath -Destination $finalPath
Write-Output "Queued $Type for $TaskId ($EventId)"
