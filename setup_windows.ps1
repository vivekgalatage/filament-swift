# FilamentSwift -- Windows Bootstrap & Setup Script
#
# Bootstraps everything needed to build and run FilamentSwift, Win32Demo, and
# WinUI3Demo on Windows (with both SwiftPM and Bazel):
#   1. Verifies Swift toolchain, Python 3, and Windows 10/11 SDK (Windows.winmd)
#   2. Downloads and extracts the prebuilt Filament SDK (.filament)
#   3. Downloads and extracts SwiftWinRT (TheBrowserCompany.SwiftWinRT 0.6.0)
#   4. Downloads and extracts Microsoft.WindowsAppSDK (1.6.250602001) NuGet package
#   5. Installs the Windows App Runtime 1.6 redistributable if not already present
#   6. Generates and patches the Swift WinRT / WinUI 3 projections
#
# Usage (from PowerShell in the repository root):
#   powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipRuntimeInstall
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$SwiftWinRtPackage = "TheBrowserCompany.SwiftWinRT"
$SwiftWinRtVersion = "0.6.0"
$WasdkPackage = "Microsoft.WindowsAppSDK"
$WasdkVersion = "1.6.250602001"
$WebView2Package = "Microsoft.Web.WebView2"
$WebView2Version = "1.0.2651.64"
$WasdkRuntimeInstallerUrl = "https://aka.ms/windowsappsdk/1.6/latest/windowsappruntimeinstall-x64.exe"

function Write-Header([string]$title) {
    Write-Host "`n====================================================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Write-Step([string]$step, [string]$title) {
    Write-Host "`n[$step] $title" -ForegroundColor Yellow
}

function Write-Pass([string]$msg) {
    Write-Host "  [OK]   $msg" -ForegroundColor Green
}

function Write-Info([string]$msg) {
    Write-Host "  [INFO] $msg" -ForegroundColor Gray
}

function Write-Warn([string]$msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
}

function Get-FileDownload([string]$Url, [string]$OutFile) {
    Write-Info "Downloading $Url ..."
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
        & curl.exe -4 -fL --retry 3 -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed with exit code $LASTEXITCODE for $Url"
        }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

function Find-Python3 {
    # Prefer real Python installs over Microsoft Store WindowsApps aliases.
    $candidates = @()
    foreach ($cmd in @("python.exe", "py.exe", "python3.exe")) {
        $found = Get-Command $cmd -All -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -notlike "*\WindowsApps\*" }
        foreach ($item in $found) {
            $candidates += $item.Source
        }
    }
    $localPythons = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending
    foreach ($py in $localPythons) {
        $candidates += $py.FullName
    }
    if (Test-Path "C:\Windows\py.exe") {
        $candidates += "C:\Windows\py.exe"
    }

    foreach ($exe in ($candidates | Select-Object -Unique)) {
        try {
            $verArgs = if ($exe -like "*\py.exe") { @("-3", "-c", "import sys; print(sys.executable)") } else { @("-c", "import sys; print(sys.executable)") }
            $out = & $exe @verArgs 2>$null
            if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path $out.Trim())) {
                return $out.Trim()
            }
        } catch {}
    }
    return $null
}

function Find-WindowsWinmd {
    $kitRoots = @()
    if ($env:WindowsSdkDir) {
        $kitRoots += $env:WindowsSdkDir.TrimEnd('\')
    }
    $kitRoots += @(
        "${env:ProgramFiles(x86)}\Windows Kits\10",
        "$env:ProgramFiles\Windows Kits\10"
    )
    foreach ($kitRoot in ($kitRoots | Select-Object -Unique)) {
        $unionDir = Join-Path $kitRoot "UnionMetadata"
        if (-not (Test-Path $unionDir)) { continue }
        $verDirs = Get-ChildItem -Path $unionDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending
        foreach ($verDir in $verDirs) {
            $candidate = Join-Path $verDir.FullName "Windows.winmd"
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }
    return $null
}

Write-Header "FilamentSwift -- Windows Setup and Bootstrap"
Write-Info "Repository Root: $RepoRoot"

# -----------------------------------------------------------------------------
# 1. Verify Toolchain Prerequisites (Swift, Python 3, Windows SDK)
# -----------------------------------------------------------------------------
Write-Step "1/6" "Checking Swift, Python 3, and Windows SDK..."

$swiftCmd = Get-Command "swift.exe" -ErrorAction SilentlyContinue
if (-not $swiftCmd) {
    throw "swift.exe not found on PATH. Install Swift 6.x for Windows from https://www.swift.org/install/windows/"
}
$swiftVer = & { $ErrorActionPreference = 'Continue'; & $swiftCmd.Source --version 2>&1 } | Select-Object -First 1
Write-Pass "Swift: $swiftVer"

$pythonExe = Find-Python3
if (-not $pythonExe) {
    throw "Python 3 not found. Install Python 3 from https://www.python.org/downloads/windows/"
}
$pyVer = & $pythonExe --version 2>&1
Write-Pass "Python: $pyVer ($pythonExe)"

$windowsWinmd = Find-WindowsWinmd
if (-not $windowsWinmd) {
    throw "Windows.winmd not found. Install the Windows 10/11 SDK via Visual Studio Installer."
}
Write-Pass "Windows.winmd: $windowsWinmd"

# -----------------------------------------------------------------------------
# 2. Bootstrap Prebuilt Filament SDK (.filament)
# -----------------------------------------------------------------------------
Write-Step "2/6" "Bootstrapping prebuilt Filament SDK (.filament)..."

$filamentHeader = Join-Path $RepoRoot ".filament\include\filament\Engine.h"
if ((Test-Path $filamentHeader) -and -not $Force) {
    Write-Pass "Filament SDK already present at $(Join-Path $RepoRoot '.filament')"
} else {
    $ensureScript = Join-Path $RepoRoot "scripts\ensure_filament.py"
    $ensureArgs = @($ensureScript)
    if ($Force) { $ensureArgs += "--force" }
    & $pythonExe @ensureArgs
    if ($LASTEXITCODE -ne 0) {
        throw "scripts/ensure_filament.py failed with exit code $LASTEXITCODE"
    }
    Write-Pass "Filament SDK installed at $(Join-Path $RepoRoot '.filament')"
}

# -----------------------------------------------------------------------------
# 3. Bootstrap SwiftWinRT (TheBrowserCompany.SwiftWinRT 0.6.0)
# -----------------------------------------------------------------------------
Write-Step "3/6" "Bootstrapping SwiftWinRT $SwiftWinRtPackage $SwiftWinRtVersion..."

$swiftWinRtDir = Join-Path $RepoRoot "WinUIProjections\_tools\swiftwinrt"
$swiftWinRtExe = Join-Path $swiftWinRtDir "bin\swiftwinrt.exe"

if ((Test-Path $swiftWinRtExe) -and -not $Force) {
    Write-Pass "swiftwinrt.exe already present at $swiftWinRtExe"
} else {
    $binDir = Join-Path $swiftWinRtDir "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }
    $nugetUrl = "https://www.nuget.org/api/v2/package/$SwiftWinRtPackage/$SwiftWinRtVersion"
    $nupkgZip = Join-Path $env:TEMP "$SwiftWinRtPackage.$SwiftWinRtVersion.zip"
    Get-FileDownload -Url $nugetUrl -OutFile $nupkgZip

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($nupkgZip)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq "bin/swiftwinrt.exe" } | Select-Object -First 1
        if (-not $entry) {
            throw "bin/swiftwinrt.exe not found inside $SwiftWinRtPackage.$SwiftWinRtVersion.nupkg"
        }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $swiftWinRtExe, $true)
    } finally {
        $zip.Dispose()
        Remove-Item $nupkgZip -Force -ErrorAction SilentlyContinue
    }
    Write-Pass "Extracted swiftwinrt.exe to $swiftWinRtExe"
}

# -----------------------------------------------------------------------------
# 4. Bootstrap Microsoft.WindowsAppSDK & Microsoft.Web.WebView2 NuGet Packages
# -----------------------------------------------------------------------------
Write-Step "4/6" "Bootstrapping $WasdkPackage ($WasdkVersion) and $WebView2Package ($WebView2Version)..."

$packagesRoot = Join-Path $RepoRoot "WinUIProjections\_packages"
$wasdkDir = Join-Path $packagesRoot "$WasdkPackage.$WasdkVersion"
$wasdkMarker = Join-Path $wasdkDir "runtimes\win-x64\native\Microsoft.WindowsAppRuntime.Bootstrap.dll"

if ((Test-Path $wasdkMarker) -and -not $Force) {
    Write-Pass "$WasdkPackage.$WasdkVersion already present at $wasdkDir"
} else {
    if (Test-Path $wasdkDir) {
        Remove-Item $wasdkDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $wasdkDir -Force | Out-Null

    $nugetUrl = "https://www.nuget.org/api/v2/package/$WasdkPackage/$WasdkVersion"
    $nupkgZip = Join-Path $env:TEMP "$WasdkPackage.$WasdkVersion.zip"
    Get-FileDownload -Url $nugetUrl -OutFile $nupkgZip

    Write-Info "Extracting $WasdkPackage.$WasdkVersion ..."
    Expand-Archive -Path $nupkgZip -DestinationPath $wasdkDir -Force
    Remove-Item $nupkgZip -Force -ErrorAction SilentlyContinue
    Write-Pass "Extracted $WasdkPackage.$WasdkVersion to $wasdkDir"
}

$webview2Dir = Join-Path $packagesRoot "$WebView2Package.$WebView2Version"
$webview2Marker = Join-Path $webview2Dir "lib\Microsoft.Web.WebView2.Core.winmd"

if ((Test-Path $webview2Marker) -and -not $Force) {
    Write-Pass "$WebView2Package.$WebView2Version already present at $webview2Dir"
} else {
    if (Test-Path $webview2Dir) {
        Remove-Item $webview2Dir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $webview2Dir -Force | Out-Null

    $nugetUrl = "https://www.nuget.org/api/v2/package/$WebView2Package/$WebView2Version"
    $nupkgZip = Join-Path $env:TEMP "$WebView2Package.$WebView2Version.zip"
    Get-FileDownload -Url $nugetUrl -OutFile $nupkgZip

    Write-Info "Extracting $WebView2Package.$WebView2Version ..."
    Expand-Archive -Path $nupkgZip -DestinationPath $webview2Dir -Force
    Remove-Item $nupkgZip -Force -ErrorAction SilentlyContinue
    Write-Pass "Extracted $WebView2Package.$WebView2Version to $webview2Dir"
}

# -----------------------------------------------------------------------------
# 5. Ensure Windows App Runtime 1.6 Redistributable is Installed
# -----------------------------------------------------------------------------
Write-Step "5/6" "Checking Windows App Runtime 1.6 redistributable..."

if ($SkipRuntimeInstall) {
    Write-Info "Skipping Windows App Runtime 1.6 installation check (-SkipRuntimeInstall)."
} else {
    $runtimePkg = Get-AppxPackage -Name "Microsoft.WindowsAppRuntime.1.6*" -ErrorAction SilentlyContinue
    if ($runtimePkg) {
        Write-Pass "Windows App Runtime 1.6 is installed ($($runtimePkg[0].Version))."
    } else {
        Write-Info "Installing Windows App Runtime 1.6 redistributable..."
        $installerExe = Join-Path $env:TEMP "windowsappruntimeinstall-x64.exe"
        try {
            Get-FileDownload -Url $WasdkRuntimeInstallerUrl -OutFile $installerExe
            $proc = Start-Process -FilePath $installerExe -ArgumentList "--quiet --norestart" -Wait -PassThru -NoNewWindow
            Remove-Item $installerExe -Force -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-Pass "Windows App Runtime 1.6 installed successfully."
            } else {
                Write-Warn "Windows App Runtime installer exited with code $($proc.ExitCode). You can also run: winget install Microsoft.WindowsAppRuntime.1.6"
            }
        } catch {
            Write-Warn "Could not auto-install Windows App Runtime 1.6: $_"
            Write-Warn "Install manually with: winget install Microsoft.WindowsAppRuntime.1.6"
        }
    }
}

# -----------------------------------------------------------------------------
# 6. Generate WinUI 3 Swift Projections
# -----------------------------------------------------------------------------
Write-Step "6/6" "Generating WinUI 3 Swift projections..."

$genScript = Join-Path $RepoRoot "WinUIProjections\scripts\generate_winui_projection.py"
& $pythonExe $genScript `
    --swiftwinrt $swiftWinRtExe `
    --nuget-dir $packagesRoot `
    --windows-winmd $windowsWinmd
if ($LASTEXITCODE -ne 0) {
    throw "generate_winui_projection.py failed with exit code $LASTEXITCODE"
}
Write-Pass "WinUI 3 Swift projections generated under WinUIProjections\Sources\"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
Write-Header "Windows Setup Complete!"
Write-Host "Build and run the demos with SwiftPM:" -ForegroundColor White
Write-Host "  swift run --package-path Examples Win32Demo" -ForegroundColor Yellow
Write-Host "  swift run --package-path Examples WinUI3Demo" -ForegroundColor Yellow
Write-Host "Or with Bazel:" -ForegroundColor White
Write-Host "  bazel run //Examples:Win32Demo" -ForegroundColor Yellow
Write-Host "  bazel run //Examples:WinUI3Demo" -ForegroundColor Yellow
Write-Host ""
