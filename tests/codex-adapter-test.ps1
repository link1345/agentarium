$ErrorActionPreference = 'Stop'
$rootPath = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $rootPath ('artifacts\adapter-tests\' + [guid]::NewGuid().ToString('N'))
$adapter = Join-Path $rootPath 'scripts\import-codex.ps1'
$stream = @(
    '{"type":"thread.started","thread_id":"example-thread"}',
    '{"type":"turn.started"}',
    '{"type":"item.started","item":{"type":"command_execution","command":"SECRET-MUST-NOT-BE-COPIED"}}',
    '{"type":"item.completed","item":{"type":"agent_message","text":"PRIVATE-MESSAGE"}}',
    '{"type":"turn.completed","usage":{"input_tokens":100}}'
)
$stream | & $adapter -TaskId adapter-test -DataDir $testPath -RunId test-run | Out-Null
$events = @(Get-ChildItem (Join-Path $testPath 'inbox') -Filter '*.json' | Sort-Object Name | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json })
if (($events.type -join ',') -ne 'task.started,tool.started,task.completed') { throw 'Wrong Codex event mapping' }
if (($events | ConvertTo-Json) -match 'SECRET|PRIVATE') { throw 'Private event content leaked' }
if ($events[-1].id -ne 'test-run:5') { throw 'Unstable event identity' }
$truncatedPath = Join-Path $testPath 'truncated'
'{"type":"turn.started"}' | & $adapter -TaskId truncated -DataDir $truncatedPath | Out-Null
$truncated = @(Get-ChildItem (Join-Path $truncatedPath 'inbox') -Filter '*.json' | Sort-Object Name | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json })
if ($truncated[-1].type -ne 'task.paused') { throw 'EOF must not imply success' }
$failedPath = Join-Path $testPath 'failed'
@('{"type":"turn.started"}','{"type":"turn.failed"}') | & $adapter -TaskId failed -DataDir $failedPath | Out-Null
$failed = @(Get-ChildItem (Join-Path $failedPath 'inbox') -Filter '*.json' | Sort-Object Name | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json })
if ($failed[-1].type -ne 'task.failed') { throw 'Failed turn must fail' }
$rejected = $false
try { 'not json' | & $adapter -DataDir (Join-Path $testPath 'invalid') | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Invalid JSON must be rejected' }
'PASS: Codex mapping, privacy, stable IDs, truncated stream, failure, invalid JSON'
