Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:KanoComfyTaskName = 'KanoComfyUI'
$script:KanoComfyTaskPath = '\Kano\GenAI\'
$script:KanoComfyAddress = '127.0.0.1'
$script:KanoComfyPort = 8188

function Resolve-KanoComfyRoot {
    if ($env:KANO_COMFYUI_ROOT) {
        return (Resolve-Path -LiteralPath $env:KANO_COMFYUI_ROOT).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Resolve-KanoComfyPython {
    param([Parameter(Mandatory = $true)][string]$ComfyRoot)

    $candidate = Join-Path $ComfyRoot '.venv\Scripts\python.exe'
    if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "ComfyUI Python was not found: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-KanoComfyTask {
    Get-ScheduledTask `
        -TaskName $script:KanoComfyTaskName `
        -TaskPath $script:KanoComfyTaskPath `
        -ErrorAction SilentlyContinue
}

function Test-KanoComfyHealth {
    param([int]$TimeoutSec = 3)

    try {
        $response = Invoke-WebRequest `
            -Uri "http://$($script:KanoComfyAddress):$($script:KanoComfyPort)/system_stats" `
            -UseBasicParsing `
            -TimeoutSec $TimeoutSec
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Get-KanoComfyPortOwner {
    $connection = Get-NetTCPConnection `
        -State Listen `
        -LocalPort $script:KanoComfyPort `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (!$connection) {
        return $null
    }
    return $connection.OwningProcess
}

function Wait-KanoComfyHealth {
    param(
        [Parameter(Mandatory = $true)][bool]$Expected,
        [int]$TimeoutSec = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        if ((Test-KanoComfyHealth) -eq $Expected) {
            return $true
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Ensure-KanoScheduledTaskFolder {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $current = $service.GetFolder('\')
    foreach ($segment in @('Kano', 'GenAI')) {
        try {
            $current = $current.GetFolder($segment)
        } catch {
            $current = $current.CreateFolder($segment)
        }
    }
}

