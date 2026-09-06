param(
    [Parameter(ValueFromPipeline=$true)][string]$InputObject,
    [string]$TaskId = ('codex-' + [guid]::NewGuid().ToString('N')),
    [string]$Title = 'Codexの作業',
    [string]$Url = '',
    [string]$RunId = [guid]::NewGuid().ToString('N'),
    [string]$DataDir = $(if ($env:AGENTARIUM_DATA_DIR) { $env:AGENTARIUM_DATA_DIR } else { Join-Path $env:APPDATA 'Godot\app_userdata\Agentarium' })
)
begin {
    $ErrorActionPreference = 'Stop'
    $sender = Join-Path $PSScriptRoot 'send-event.ps1'
    $lineNumber = 0
    $activeTurn = $false
    function Publish-CodexEvent([string]$Kind, [string]$Summary) {
        # RunId + line number make replay idempotent within the receiver's retention window.
        & $sender -TaskId $TaskId -Type $Kind -Title $Title -Pet fox -Url $Url -Summary $Summary -EventId "${RunId}:${lineNumber}" -DataDir $DataDir
    }
}
process {
    $lineNumber++
    if (-not [string]::IsNullOrWhiteSpace($InputObject)) {
        if ($InputObject.Length -gt 1048576) { throw "Codex JSONL line $lineNumber exceeds 1 MiB." }
        try { $item = $InputObject | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
        catch { throw "Invalid Codex JSONL at line $lineNumber (content omitted)." }
        if ($item -isnot [System.Collections.IDictionary]) { throw "Codex JSONL line $lineNumber is not an object." }
        switch ($item.type) {
            'turn.started' {
                $activeTurn = $true
                Publish-CodexEvent 'task.started' 'Codexが作業を始めました。'
            }
            'item.started' {
                if ($activeTurn -and $item.item -is [System.Collections.IDictionary]) {
                    $summary = switch ($item.item.type) {
                        'command_execution' { 'コマンドを実行しています。' }
                        'file_change' { 'ファイルを変更しています。' }
                        'mcp_tool_call' { 'ツールを使っています。' }
                        'web_search' { '資料を調べています。' }
                        default { $null }
                    }
                    if ($summary) { Publish-CodexEvent 'tool.started' $summary }
                }
            }
            'turn.completed' {
                $activeTurn = $false
                Publish-CodexEvent 'task.completed' 'Codexの作業が完了しました。元の画面で成果物を確認してください。'
            }
            'turn.failed' {
                $activeTurn = $false
                Publish-CodexEvent 'task.failed' 'Codexの作業が失敗しました。元の画面を確認してください。'
            }
            'error' {
                $activeTurn = $false
                Publish-CodexEvent 'task.failed' 'Codexがエラーを報告しました。元の画面を確認してください。'
            }
        }
    }
}
end {
    if ($activeTurn) {
        $lineNumber++
        Publish-CodexEvent 'task.paused' 'イベントの接続が終了しました。作業完了は未確認です。'
    }
}
