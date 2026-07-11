param([int]$TimeoutSec = 90)

. (Join-Path $PSScriptRoot 'common.ps1')

$Task = Get-KanoComfyTask
if (!$Task) {
    throw "Scheduled task is not registered: $($script:KanoComfyTaskPath)$($script:KanoComfyTaskName)"
}
if (Test-KanoComfyHealth) {
    Write-Host '[DONE] ComfyUI is already healthy at http://127.0.0.1:8188/.'
    exit 0
}

Start-ScheduledTask -InputObject $Task
if (!(Wait-KanoComfyHealth -Expected $true -TimeoutSec $TimeoutSec)) {
    $Task = Get-KanoComfyTask
    throw "ComfyUI did not become healthy within ${TimeoutSec}s. Task state: $($Task.State)"
}
Write-Host '[DONE] ComfyUI is healthy at http://127.0.0.1:8188/.'

