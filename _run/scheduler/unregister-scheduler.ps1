param([switch]$Stop)

. (Join-Path $PSScriptRoot 'common.ps1')

$Task = Get-KanoComfyTask
if (!$Task) {
    Write-Host '[DONE] Scheduled task is already absent.'
    exit 0
}
if ($Stop -and $Task.State -ne 'Ready') {
    & (Join-Path $PSScriptRoot 'stop-scheduler.ps1')
}
Unregister-ScheduledTask `
    -TaskName $script:KanoComfyTaskName `
    -TaskPath $script:KanoComfyTaskPath `
    -Confirm:$false
Write-Host '[DONE] ComfyUI scheduled task unregistered.'

