param([int]$TimeoutSec = 60)

. (Join-Path $PSScriptRoot 'common.ps1')

$Task = Get-KanoComfyTask
if (!$Task) {
    throw "Scheduled task is not registered: $($script:KanoComfyTaskPath)$($script:KanoComfyTaskName)"
}
if ($Task.State -ne 'Ready') {
    Stop-ScheduledTask -InputObject $Task
}
Start-Sleep -Seconds 2
if (Test-KanoComfyHealth) {
    $ComfyRoot = Resolve-KanoComfyRoot
    $VenvPython = Resolve-KanoComfyPython -ComfyRoot $ComfyRoot
    $ExpectedPython = (& $VenvPython -c 'import sys; print(getattr(sys, "_base_executable", sys.executable))').Trim().ToLowerInvariant()
    $ExpectedMain = (Join-Path $ComfyRoot 'main.py').ToLowerInvariant()
    $PidFile = Join-Path $ComfyRoot '_run\logs\scheduler\comfyui.pid'
    $owner = Get-KanoComfyPortOwner
    $process = if ($owner) {
        Get-CimInstance Win32_Process -Filter "ProcessId=$owner" -ErrorAction SilentlyContinue
    } else {
        $null
    }
    $actualExecutable = if ($process -and $process.ExecutablePath) { $process.ExecutablePath.ToLowerInvariant() } else { '' }
    $actualCommand = if ($process -and $process.CommandLine) { $process.CommandLine.ToLowerInvariant() } else { '' }
    $recordedOwner = if (Test-Path -LiteralPath $PidFile) {
        [int](Get-Content -LiteralPath $PidFile -Raw).Trim()
    } else {
        0
    }
    $ownedByPidFile = `
        $recordedOwner -eq $owner -or `
        ($process -and $recordedOwner -eq $process.ParentProcessId)
    $ownedByExactCommand = `
        $actualExecutable -eq $ExpectedPython -and `
        $actualCommand.Contains($ExpectedMain) -and `
        $actualCommand.Contains('--listen 127.0.0.1') -and `
        $actualCommand.Contains('--port 8188')
    if (!$process -or (!$ownedByPidFile -and !$ownedByExactCommand)) {
        throw "Port 8188 stayed healthy after task stop, but PID $owner could not be proven to be the owned ComfyUI process."
    }
    Write-Host "[INFO] Stopping owned ComfyUI child PID $owner..."
    Stop-Process -Id $owner
    if ($ownedByPidFile -and (Test-Path -LiteralPath $PidFile)) {
        Remove-Item -LiteralPath $PidFile -Force
    }
}
if (!(Wait-KanoComfyHealth -Expected $false -TimeoutSec $TimeoutSec)) {
    $owner = Get-KanoComfyPortOwner
    throw "ComfyUI still answers after the scheduled task stopped. Port owner PID: $owner"
}
Write-Host '[DONE] Scheduled ComfyUI is stopped and port 8188 is closed.'
