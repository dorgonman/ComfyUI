. (Join-Path $PSScriptRoot 'common.ps1')

$Task = Get-KanoComfyTask
$owner = Get-KanoComfyPortOwner
[pscustomobject]@{
    task = "$($script:KanoComfyTaskPath)$($script:KanoComfyTaskName)"
    registered = [bool]$Task
    task_state = if ($Task) { [string]$Task.State } else { 'NotRegistered' }
    healthy = Test-KanoComfyHealth
    endpoint = 'http://127.0.0.1:8188/'
    port_owner_pid = $owner
    legacy_port_8191_listening = [bool](Get-NetTCPConnection -State Listen -LocalPort 8191 -ErrorAction SilentlyContinue)
} | ConvertTo-Json

