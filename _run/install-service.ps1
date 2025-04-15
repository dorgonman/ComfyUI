try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    Write-Warning "Failed to set UTF-8 output encoding"
}

Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

$ErrorActionPreference = 'Stop'

# Get current script directory
$workingDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
echo "Working Directory: $workingDir"

# Define service name
$serviceName = "ComfyUI"

# Ensure logs directory exists
$logDir = Join-Path $workingDir "logs"
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
$stdout = Join-Path $logDir "stdout.log"
$stderr = Join-Path $logDir "stderr.log"

# Stop and remove existing service
Write-Host "[INFO] Checking if service '$serviceName' exists..."
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "[INFO] Stopping existing service..."
    Stop-Service -Name $serviceName -Force

    Write-Host "[INFO] Removing existing service..."
    Start-Process -Wait -NoNewWindow -FilePath "nssm.exe" -ArgumentList "remove $serviceName confirm"
}

# Install the service using cmd.exe
Write-Host "[INFO] Installing new service '$serviceName'..."
Start-Process -Wait -NoNewWindow -FilePath "nssm.exe" -ArgumentList @(
    "install", $serviceName,
    "$workingDir\run.bat"
)

# Configure service settings
Write-Host "[INFO] Configuring service..."
nssm set $serviceName AppDirectory "$workingDir"
nssm set $serviceName AppRestartDelay 10000
nssm set $serviceName AppThrottle 3000
nssm set $serviceName Start SERVICE_AUTO_START
nssm set $serviceName AppExit Default Restart

# Set log paths (for NSSM UI, optional but consistent)
nssm set $serviceName AppStdout $stdout
nssm set $serviceName AppStderr $stderr
nssm edit $serviceName
# Start the service
Write-Host "[INFO] Starting service..."
Start-Service -Name $serviceName

Write-Host "[DONE] '$serviceName' installed and started successfully."