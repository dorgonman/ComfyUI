. (Join-Path $PSScriptRoot 'common.ps1')

$Checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $Checks.Add([pscustomobject]@{ name = $Name; passed = $Passed; detail = $Detail })
}

$ComfyRoot = Resolve-KanoComfyRoot
$Python = Join-Path $ComfyRoot '.venv\Scripts\python.exe'
$Task = Get-KanoComfyTask
$LegacyService = Get-Service -Name 'ComfyUI' -ErrorAction SilentlyContinue

Add-Check 'comfy_root' (Test-Path -LiteralPath (Join-Path $ComfyRoot 'main.py')) $ComfyRoot
Add-Check 'python' (Test-Path -LiteralPath $Python) $Python
Add-Check 'task_registered' ([bool]$Task) "$($script:KanoComfyTaskPath)$($script:KanoComfyTaskName)"
if ($Task) {
    $Principal = (Get-ScheduledTask -TaskName $script:KanoComfyTaskName -TaskPath $script:KanoComfyTaskPath).Principal
    Add-Check 'interactive_principal' ($Principal.UserId -ne 'SYSTEM' -and $Principal.LogonType -eq 'Interactive') "$($Principal.UserId) / $($Principal.LogonType)"
}
Add-Check 'legacy_service_absent' (!$LegacyService) $(if ($LegacyService) { "$($LegacyService.Status) / $($LegacyService.StartType)" } else { 'absent' })
Add-Check 'canonical_endpoint' (Test-KanoComfyHealth) 'http://127.0.0.1:8188/system_stats'
Add-Check 'legacy_port_closed' (![bool](Get-NetTCPConnection -State Listen -LocalPort 8191 -ErrorAction SilentlyContinue)) 'port 8191'
Add-Check 'shared_input' (Test-Path -LiteralPath (Join-Path $ComfyRoot 'input\shared\AGENTS.md')) 'input/shared/AGENTS.md'
Add-Check 'project_input' (Test-Path -LiteralPath (Join-Path $ComfyRoot 'input\project\KTO\AGENTS.md')) 'input/project/KTO/AGENTS.md'
Add-Check 'project_workflows' (Test-Path -LiteralPath (Join-Path $ComfyRoot 'user\default\workflows\KTO\AGENTS.md')) 'workflows/KTO/AGENTS.md'
Add-Check 'custom_node_rules' (Test-Path -LiteralPath (Join-Path $ComfyRoot 'custom_nodes\kano-comfyui-custom-node\AGENTS.md')) 'custom node AGENTS.md'

if (Test-KanoComfyHealth) {
    try {
        $ObjectInfo = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/object_info/KanoThreeViewSheet' -TimeoutSec 10
        Add-Check 'kano_three_view_node' ([bool]$ObjectInfo.KanoThreeViewSheet) 'KanoThreeViewSheet'
    } catch {
        Add-Check 'kano_three_view_node' $false $_.Exception.Message
    }
}

$Checks | Format-Table -AutoSize
if ($Checks.Where({ !$_.passed }).Count -gt 0) {
    throw 'ComfyUI scheduler doctor found one or more failed checks.'
}
Write-Host '[DONE] All ComfyUI scheduler checks passed.'

