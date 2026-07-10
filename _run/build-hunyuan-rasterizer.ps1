#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PythonPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDir,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BuildRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "This helper supports Windows only."
}

$SmokeCode = @'
import math
import torch

if not torch.cuda.is_available():
    raise RuntimeError("CUDA is not available to PyTorch")

import custom_rasterizer as cr

device = torch.device("cuda")
positions = torch.tensor(
    [[[-0.5, -0.5, 0.5, 1.0], [0.5, -0.5, 0.5, 1.0], [0.0, 0.5, 0.5, 1.0]]],
    dtype=torch.float32,
    device=device,
)
triangles = torch.tensor([[0, 1, 2]], dtype=torch.int32, device=device)
face_indices, barycentric = cr.rasterize(positions, triangles, (32, 32))
torch.cuda.synchronize()

if tuple(face_indices.shape) != (32, 32):
    raise RuntimeError(f"unexpected face-index shape: {tuple(face_indices.shape)}")
if tuple(barycentric.shape) != (32, 32, 3):
    raise RuntimeError(f"unexpected barycentric shape: {tuple(barycentric.shape)}")

covered_pixels = int((face_indices > 0).sum().item())
barycentric_sum = float(barycentric.sum().item())
if covered_pixels <= 0:
    raise RuntimeError("triangle rasterization produced no covered pixels")
if not math.isfinite(barycentric_sum) or barycentric_sum <= 0.0:
    raise RuntimeError("triangle rasterization produced invalid barycentric weights")

print(
    "custom_rasterizer CUDA smoke OK: "
    f"faces={tuple(face_indices.shape)} barycentric={tuple(barycentric.shape)} "
    f"covered={covered_pixels} weight_sum={barycentric_sum:.3f}"
)
'@

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Test-IsStrictChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Parent,

        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    $prefix = $parentFull + [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathEquals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,

        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    return $leftFull.Equals($rightFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-RasterizerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Python,

        [switch]$ShowFailure
    )

    $pythonDirectory = [System.IO.Path]::GetDirectoryName($Python)
    Push-Location -LiteralPath $pythonDirectory
    try {
        $output = @(& $Python -c $SmokeCode 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($exitCode -eq 0) {
        foreach ($line in $output) {
            Write-Host $line
        }
        return $true
    }

    if ($ShowFailure) {
        foreach ($line in $output) {
            Write-Warning ([string]$line)
        }
    }

    return $false
}

function Find-VcVars64 {
    $vswhereCandidates = @()
    if (${env:ProgramFiles(x86)}) {
        $vswhereCandidates += Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    }
    if ($env:ProgramFiles) {
        $vswhereCandidates += Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe"
    }

    foreach ($vswhere in ($vswhereCandidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
            continue
        }

        $installations = @(
            & $vswhere -latest -products "*" -version "[17.0,18.0)" `
                -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" `
                -property installationPath 2>$null
        )
        if ($LASTEXITCODE -ne 0) {
            continue
        }

        foreach ($installation in $installations) {
            if ([string]::IsNullOrWhiteSpace([string]$installation)) {
                continue
            }

            $candidate = Join-Path ([string]$installation).Trim() "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).ProviderPath
            }
        }
    }

    if ($env:ProgramFiles) {
        $vs2022Root = Join-Path $env:ProgramFiles "Microsoft Visual Studio\2022"
        if (Test-Path -LiteralPath $vs2022Root -PathType Container) {
            foreach ($edition in (Get-ChildItem -LiteralPath $vs2022Root -Directory | Sort-Object Name)) {
                $candidate = Join-Path $edition.FullName "VC\Auxiliary\Build\vcvars64.bat"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return (Resolve-Path -LiteralPath $candidate).ProviderPath
                }
            }
        }
    }

    throw "Visual Studio 2022 with the MSVC x64 toolchain was not found."
}

function Test-Cuda12Root {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $false
    }

    $nvcc = Join-Path $Candidate "bin\nvcc.exe"
    if (-not (Test-Path -LiteralPath $nvcc -PathType Leaf)) {
        return $false
    }

    $versionOutput = @(& $nvcc --version 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return $false
    }

    return (($versionOutput -join "`n") -match "release\s+12\.")
}

function Find-Cuda12Root {
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($environmentPath in @($env:CUDA_PATH, $env:CUDA_HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($environmentPath)) {
            $candidates.Add($environmentPath)
        }
    }

    $nvccCommand = Get-Command "nvcc.exe" -ErrorAction SilentlyContinue
    if ($null -ne $nvccCommand) {
        $candidates.Add((Split-Path (Split-Path $nvccCommand.Source -Parent) -Parent))
    }

    if ($env:ProgramFiles) {
        $cudaParent = Join-Path $env:ProgramFiles "NVIDIA GPU Computing Toolkit\CUDA"
        if (Test-Path -LiteralPath $cudaParent -PathType Container) {
            foreach ($cudaDirectory in (
                Get-ChildItem -LiteralPath $cudaParent -Directory -Filter "v12.*" |
                    Sort-Object Name -Descending
            )) {
                $candidates.Add($cudaDirectory.FullName)
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($candidate in $candidates) {
        $candidateFull = [System.IO.Path]::GetFullPath($candidate)
        if (-not $seen.Add($candidateFull)) {
            continue
        }
        if (Test-Cuda12Root -Candidate $candidateFull) {
            return (Resolve-Path -LiteralPath $candidateFull).ProviderPath
        }
    }

    throw "A CUDA Toolkit 12.x installation with nvcc.exe was not found."
}

function Import-VcVarsEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VcVars64
    )

    if ([string]::IsNullOrWhiteSpace($env:ComSpec) -or -not (Test-Path -LiteralPath $env:ComSpec)) {
        throw "cmd.exe was not found through ComSpec."
    }

    # Capture, but never print, the environment because it can contain credentials.
    $command = "call `"$VcVars64`" >nul 2>&1 && set"
    $environmentLines = @(& $env:ComSpec /d /s /c $command)
    if ($LASTEXITCODE -ne 0) {
        throw "vcvars64.bat failed to initialize the MSVC environment."
    }

    foreach ($line in $environmentLines) {
        $text = [string]$line
        $separator = $text.IndexOf("=")
        if ($separator -le 0) {
            continue
        }

        $name = $text.Substring(0, $separator)
        if ($name.StartsWith("=", [System.StringComparison]::Ordinal)) {
            continue
        }

        $value = $text.Substring($separator + 1)
        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }

    if ($null -eq (Get-Command "cl.exe" -ErrorAction SilentlyContinue)) {
        throw "vcvars64.bat completed, but cl.exe is not available."
    }
}

function Patch-SetupForMsvc {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SetupPath
    )

    $setupText = [System.IO.File]::ReadAllText($SetupPath)
    $pattern = '(?<prefix>["'']cxx["'']\s*:\s*\[)(?<flags>[^\]]*)(?<suffix>\])'
    $match = [System.Text.RegularExpressions.Regex]::Match($setupText, $pattern)
    if (-not $match.Success) {
        throw "setup.py does not contain a literal cxx compile-flag list."
    }

    $flags = $match.Groups["flags"].Value
    if (($flags -notmatch '-std=c\+\+20') -and ($flags -notmatch '/std:c\+\+20')) {
        throw "setup.py cxx flags do not contain the expected C++20 option."
    }

    $patchedFlags = $flags.Replace('"-O3"', '"/O2"')
    $patchedFlags = $patchedFlags.Replace("'-O3'", "'/O2'")
    $patchedFlags = $patchedFlags.Replace('"-std=c++20"', '"/std:c++20"')
    $patchedFlags = $patchedFlags.Replace("'-std=c++20'", "'/std:c++20'")
    if ($patchedFlags -notmatch '/std:c\+\+20') {
        throw "Failed to convert setup.py cxx flags to MSVC syntax."
    }

    $replacement = $match.Groups["prefix"].Value + $patchedFlags + $match.Groups["suffix"].Value
    $patchedText = $setupText.Substring(0, $match.Index) + $replacement + `
        $setupText.Substring($match.Index + $match.Length)
    [System.IO.File]::WriteAllText(
        $SetupPath,
        $patchedText,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$pythonFull = Resolve-ExistingPath -Path $PythonPath -Description "Python executable"
if (-not (Test-Path -LiteralPath $pythonFull -PathType Leaf)) {
    throw "PythonPath must identify a file: $PythonPath"
}

$sourceFull = Resolve-ExistingPath -Path $SourceDir -Description "Rasterizer source directory"
if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) {
    throw "SourceDir must identify a directory: $SourceDir"
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceFull "setup.py") -PathType Leaf)) {
    throw "Rasterizer source does not contain setup.py: $sourceFull"
}

if (Invoke-RasterizerSmoke -Python $pythonFull) {
    Write-Host "Compatible custom_rasterizer binary is already installed."
    exit 0
}

Write-Host "custom_rasterizer CUDA smoke failed; rebuilding for the active PyTorch environment."

$metadataOutput = @(
    & $pythonFull -c `
        'import json, sys, torch; print(json.dumps({"python": f"{sys.version_info.major}.{sys.version_info.minor}", "torch": torch.__version__.split("+")[0]}))' `
        2>&1
)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query Python and PyTorch build metadata."
}
$metadata = ($metadataOutput[-1] | ConvertFrom-Json)
$scopeName = "custom-rasterizer-py$($metadata.python.Replace('.', ''))-torch$($metadata.torch.Replace('.', '_'))-sm86"

$buildRootFull = [System.IO.Path]::GetFullPath($BuildRoot)
New-Item -ItemType Directory -Path $buildRootFull -Force | Out-Null
$buildRootFull = (Resolve-Path -LiteralPath $buildRootFull).ProviderPath
$buildDir = [System.IO.Path]::GetFullPath((Join-Path $buildRootFull $scopeName))

if (-not (Test-IsStrictChildPath -Parent $buildRootFull -Candidate $buildDir)) {
    throw "Refusing to use a build directory outside BuildRoot."
}
if (
    (Test-PathEquals -Left $sourceFull -Right $buildRootFull) -or
    (Test-IsStrictChildPath -Parent $sourceFull -Candidate $buildRootFull)
) {
    throw "BuildRoot must not be SourceDir or one of its descendants."
}
if (
    (Test-PathEquals -Left $sourceFull -Right $buildDir) -or
    (Test-IsStrictChildPath -Parent $buildDir -Candidate $sourceFull)
) {
    throw "Refusing to clean a build directory that contains SourceDir."
}

if (Test-Path -LiteralPath $buildDir) {
    $existingBuildDir = Get-Item -LiteralPath $buildDir -Force
    if (($existingBuildDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to clean a build directory that is a reparse point."
    }
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $buildDir | Out-Null
foreach ($item in (Get-ChildItem -LiteralPath $sourceFull -Force)) {
    Copy-Item -LiteralPath $item.FullName -Destination $buildDir -Recurse -Force
}

$setupPath = Join-Path $buildDir "setup.py"
Patch-SetupForMsvc -SetupPath $setupPath

$vcVars64 = Find-VcVars64
$cudaRoot = Find-Cuda12Root
Import-VcVarsEnvironment -VcVars64 $vcVars64

$env:CUDA_HOME = $cudaRoot
$env:CUDA_PATH = $cudaRoot
$env:TORCH_CUDA_ARCH_LIST = "8.6"
$env:DISTUTILS_USE_SDK = "1"
$env:PATH = (Join-Path $cudaRoot "bin") + [System.IO.Path]::PathSeparator + $env:PATH

Write-Host "Building custom_rasterizer for Python $($metadata.python), PyTorch $($metadata.torch), and CUDA architecture 8.6."
Push-Location -LiteralPath $buildDir
try {
    & $pythonFull setup.py build_ext --inplace
    if ($LASTEXITCODE -ne 0) {
        throw "custom_rasterizer native build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$builtPyd = Get-ChildItem -LiteralPath $buildDir -File -Filter "custom_rasterizer_kernel*.pyd" |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if ($null -eq $builtPyd) {
    $builtPyd = Get-ChildItem -LiteralPath $buildDir -Recurse -File -Filter "custom_rasterizer_kernel*.pyd" |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}
if ($null -eq $builtPyd) {
    throw "Build completed without producing custom_rasterizer_kernel*.pyd."
}

$sitePackagesOutput = @(
    & $pythonFull -c 'import sysconfig; print(sysconfig.get_paths()["platlib"])' 2>&1
)
if ($LASTEXITCODE -ne 0 -or $sitePackagesOutput.Count -eq 0) {
    throw "Unable to locate the active Python environment's site-packages directory."
}
$sitePackages = [string]$sitePackagesOutput[-1]
if (-not (Test-Path -LiteralPath $sitePackages -PathType Container)) {
    throw "The active Python site-packages directory does not exist."
}

$destinationPyd = Join-Path $sitePackages $builtPyd.Name
Copy-Item -LiteralPath $builtPyd.FullName -Destination $destinationPyd -Force

if (-not (Invoke-RasterizerSmoke -Python $pythonFull -ShowFailure)) {
    throw "The rebuilt custom_rasterizer failed its CUDA triangle smoke test."
}

Write-Host "Installed and validated the rebuilt custom_rasterizer kernel."
