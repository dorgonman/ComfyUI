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
$workingDir = Split-Path -Parent $workingDir
echo "Working Directory: $workingDir"

# Define service name
$serviceName = "ComfyUI"

nssm remove $serviceName confirm