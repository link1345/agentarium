param(
    [Parameter(Mandatory)][string]$Executable,
    [string[]]$ArgumentList = @(),
    [string]$TaskId = ('process-' + [guid]::NewGuid().ToString('N')),
    [string]$Title = 'ローカルの作業',
    [ValidateSet('fox','dog','bird','cat')][string]$Pet = 'dog',
    [string]$Url = '',
    [string]$DataDir = $(if ($env:AGENTARIUM_DATA_DIR) { $env:AGENTARIUM_DATA_DIR } else { Join-Path $env:APPDATA 'Godot\app_userdata\Agentarium' })
)
# Runs only the executable and argument array explicitly passed by the caller.
# Never evaluates a shell command string; process output stays in this terminal.
$ErrorActionPreference = 'Stop'
$sender = Join-Path $PSScriptRoot 'send-event.ps1'
$common = @{TaskId=$TaskId;Title=$Title;Pet=$Pet;Url=$Url;DataDir=$DataDir}
& $sender @common -Type task.started -Summary 'ローカルの処理を実行しています。' -Sequence 1
try {
    $global:LASTEXITCODE = 0
    & $Executable @ArgumentList
    $taskExitCode = $LASTEXITCODE
} catch {
    & $sender @common -Type task.failed -Summary 'プロセスを開始または実行できませんでした。ターミナルを確認してください。' -Sequence 2
    throw
}
if ($taskExitCode -eq 0) {
    & $sender @common -Type task.completed -Summary '処理が正常に終了しました。成果物を確認してください。' -Sequence 2
} else {
    & $sender @common -Type task.failed -Summary "処理が終了コード $taskExitCode で失敗しました。" -Sequence 2
}
exit $taskExitCode
