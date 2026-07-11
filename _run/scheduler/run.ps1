param(
    [ValidateSet('shared', 'exclusive')]
    [string]$Profile = 'shared'
)

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    Write-Warning 'Failed to set UTF-8 output encoding.'
}

$ComfyRoot = Resolve-KanoComfyRoot
$Python = Resolve-KanoComfyPython -ComfyRoot $ComfyRoot
$Main = Join-Path $ComfyRoot 'main.py'
if (!(Test-Path -LiteralPath $Main -PathType Leaf)) {
    throw "ComfyUI main.py was not found: $Main"
}

$LogDir = Join-Path $ComfyRoot '_run\logs\scheduler'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Transcript = Join-Path $LogDir ('comfyui-{0:yyyyMMdd}.log' -f (Get-Date))
$PidFile = Join-Path $LogDir 'comfyui.pid'
Start-Transcript -Path $Transcript -Append | Out-Null

try {
    if (Test-KanoComfyHealth) {
        Write-Host '[INFO] ComfyUI is already healthy on the canonical endpoint.'
        exit 0
    }

    $owner = Get-KanoComfyPortOwner
    if ($owner) {
        throw "Port $($script:KanoComfyPort) is occupied by PID $owner, but the ComfyUI health check failed."
    }

    if ($Profile -eq 'exclusive') {
        $limit = 6144
        if ($env:KANO_COMFYUI_EXCLUSIVE_MAX_USED_MB) {
            $limit = [int]$env:KANO_COMFYUI_EXCLUSIVE_MAX_USED_MB
        }
        $nvidiaSmi = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
        if (!$nvidiaSmi) {
            throw 'Exclusive profile requires nvidia-smi.exe for the GPU occupancy guard.'
        }
        $usedText = & $nvidiaSmi.Source '--query-gpu=memory.used' '--format=csv,noheader,nounits' |
            Select-Object -First 1
        $used = [int]$usedText.Trim()
        if ($used -gt $limit) {
            throw "Exclusive profile refused startup: GPU memory used is ${used} MB; limit is ${limit} MB."
        }
    }

    $env:HF_HOME = Join-Path $ComfyRoot 'models\huggingface'
    $env:HF_HUB_DISABLE_XET = '1'
    $env:HF_HUB_DOWNLOAD_TIMEOUT = '60'
    $env:PYTHONIOENCODING = 'utf-8'

    $Arguments = @(
        '-s',
        $Main,
        '--windows-standalone-build',
        '--listen', $script:KanoComfyAddress,
        '--port', [string]$script:KanoComfyPort
    )

    Write-Host "[INFO] Starting ComfyUI profile=$Profile endpoint=http://$($script:KanoComfyAddress):$($script:KanoComfyPort)/"
    Push-Location $ComfyRoot
    try {
        $Process = Start-Process `
            -FilePath $Python `
            -ArgumentList $Arguments `
            -WorkingDirectory $ComfyRoot `
            -NoNewWindow `
            -PassThru
        [IO.File]::WriteAllText($PidFile, [string]$Process.Id)
        $Process.WaitForExit()
        exit $Process.ExitCode
    } finally {
        if (Test-Path -LiteralPath $PidFile) {
            Remove-Item -LiteralPath $PidFile -Force
        }
        Pop-Location
    }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
