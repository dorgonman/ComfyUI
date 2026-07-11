param(
    [ValidateSet('shared', 'exclusive')]
    [string]$Profile = 'shared'
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Migration must run once from an elevated PowerShell because the legacy LocalSystem service must be stopped and deleted.'
}

$Register = Join-Path $PSScriptRoot 'register-scheduler.ps1'
$Start = Join-Path $PSScriptRoot 'start-scheduler.ps1'
$Service = Get-Service -Name 'ComfyUI' -ErrorAction SilentlyContinue

& $Register -Profile $Profile -Replace

if ($Service) {
    Write-Host '[INFO] Stopping legacy NSSM ComfyUI service...'
    Stop-Service -Name 'ComfyUI' -Force
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri 'http://127.0.0.1:8188/system_stats' -UseBasicParsing -TimeoutSec 2 | Out-Null
            Start-Sleep -Milliseconds 750
        } catch {
            break
        }
    }
}

try {
    & $Start -TimeoutSec 120
} catch {
    if ($Service) {
        Write-Warning 'Scheduled startup failed; restarting the legacy service as rollback.'
        Start-Service -Name 'ComfyUI'
    }
    throw
}

if ($Service) {
    sc.exe delete ComfyUI | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'Scheduled ComfyUI is healthy, but deleting the legacy service failed.'
    }
}

Write-Host '[DONE] ComfyUI now runs from the interactive-user scheduled task; the legacy service is absent.'

