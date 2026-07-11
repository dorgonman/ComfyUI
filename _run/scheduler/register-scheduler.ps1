param(
    [ValidateSet('shared', 'exclusive')]
    [string]$Profile = 'shared',
    [switch]$Replace
)

. (Join-Path $PSScriptRoot 'common.ps1')

$ComfyRoot = Resolve-KanoComfyRoot
$null = Resolve-KanoComfyPython -ComfyRoot $ComfyRoot
$RunScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'run.ps1')).Path
$Existing = Get-KanoComfyTask
if ($Existing -and !$Replace) {
    throw "Scheduled task already exists: $($script:KanoComfyTaskPath)$($script:KanoComfyTaskName). Use -Replace to update it."
}
if ($Existing) {
    Unregister-ScheduledTask `
        -TaskName $script:KanoComfyTaskName `
        -TaskPath $script:KanoComfyTaskPath `
        -Confirm:$false
}

Ensure-KanoScheduledTaskFolder

$PowerShell = (Get-Process -Id $PID).Path
if (!(Test-Path -LiteralPath $PowerShell -PathType Leaf)) {
    throw "Current PowerShell executable was not found: $PowerShell"
}
$ActionArgs = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$RunScript`" -Profile $Profile"
$Action = New-ScheduledTaskAction `
    -Execute $PowerShell `
    -Argument $ActionArgs `
    -WorkingDirectory $ComfyRoot
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $Identity
$Principal = New-ScheduledTaskPrincipal `
    -UserId $Identity `
    -LogonType Interactive `
    -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $script:KanoComfyTaskName `
    -TaskPath $script:KanoComfyTaskPath `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Kano ComfyUI ($Profile profile, loopback port 8188)" | Out-Null

Write-Host "[DONE] Registered $($script:KanoComfyTaskPath)$($script:KanoComfyTaskName) for $Identity."
Write-Host "[INFO] Profile: $Profile"
Write-Host '[INFO] Trigger: AtLogOn; run level: Limited; endpoint: 127.0.0.1:8188'
