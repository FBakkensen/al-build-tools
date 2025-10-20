<#
.SYNOPSIS
    Sets up infrastructure prerequisites for AL Build Tools.

.DESCRIPTION
    Installs and configures required tools:
    - Git (optional, for repository management)
    - .NET SDK 8 (for AL compiler and symbol downloads)
    - NuGet package sources (for dotnet tool installations)
    - InvokeBuild PowerShell module (for task orchestration)

    This script can be used standalone for CI/container environments or called by install.ps1.

.PARAMETER SkipGit
    Skip Git installation and configuration checks.

.PARAMETER SkipDotNet
    Skip .NET SDK installation.

.PARAMETER SkipInvokeBuild
    Skip InvokeBuild module installation.

.PARAMETER NonInteractive
    Run in non-interactive mode (automatically decline optional installations).

.EXAMPLE
    # Full setup for CI environment
    $env:ALBT_AUTO_INSTALL = '1'
    .\setup-infrastructure.ps1

.EXAMPLE
    # Container setup (skip Git, focus on build tools)
    .\setup-infrastructure.ps1 -SkipGit

.EXAMPLE
    # Manual setup with prompts
    .\setup-infrastructure.ps1
#>

#requires -Version 7.2

[CmdletBinding()]
param(
    [switch]$SkipGit,
    [switch]$SkipDotNet,
    [switch]$SkipInvokeBuild,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check for auto-install mode
$script:AutoInstall = $false
if ($env:ALBT_AUTO_INSTALL -and $env:ALBT_AUTO_INSTALL.ToString().ToLowerInvariant() -in @('1','true','yes')) {
    $script:AutoInstall = $true
}

if ($NonInteractive) {
    $script:AutoInstall = $false  # Explicitly decline installations in non-interactive mode
}

Write-Host "[setup] === AL Build Tools Infrastructure Setup ===" -ForegroundColor Cyan
Write-Host "[setup] Mode: $(if ($script:AutoInstall) { 'Auto-Install' } elseif ($NonInteractive) { 'Non-Interactive' } else { 'Interactive' })" -ForegroundColor Gray

# ============================================================================
# Git Setup
# ============================================================================
if (-not $SkipGit) {
    Write-Host "[setup] Checking Git..." -ForegroundColor Yellow

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitVersion = & git --version 2>$null
        Write-Host "[setup] ✓ Git found: $gitVersion" -ForegroundColor Green

        # Check git config
        $userName = & git config --global --get user.name 2>$null
        $userEmail = & git config --global --get user.email 2>$null

        if ($userName -and $userEmail) {
            Write-Host "[setup] ✓ Git configured: $userName <$userEmail>" -ForegroundColor Green
        } elseif ($script:AutoInstall) {
            Write-Host "[setup] Configuring Git with CI credentials..." -ForegroundColor Yellow
            & git config --global user.email "ci@albt.test" 2>&1 | Out-Null
            & git config --global user.name "AL Build Tools CI" 2>&1 | Out-Null
            Write-Host "[setup] ✓ Git configured" -ForegroundColor Green
        } else {
            Write-Host "[setup] ! Git not configured globally" -ForegroundColor Yellow
            Write-Host "[setup] Run: git config --global user.name 'Your Name'" -ForegroundColor Gray
            Write-Host "[setup]      git config --global user.email 'your@email.com'" -ForegroundColor Gray
        }
    } else {
        Write-Host "[setup] ✗ Git not found" -ForegroundColor Red
        if (-not $script:AutoInstall) {
            Write-Host "[setup] Install Git from: https://git-scm.com/download/win" -ForegroundColor Gray
        }
        exit 1
    }
}

# ============================================================================
# .NET SDK Setup
# ============================================================================
if (-not $SkipDotNet) {
    Write-Host "[setup] Checking .NET SDK..." -ForegroundColor Yellow

    $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnetCmd) {
        $dotnetVersion = & dotnet --version 2>&1
        Write-Host "[setup] ✓ .NET SDK found: $dotnetVersion" -ForegroundColor Green

        # Check NuGet sources
        Write-Host "[setup] Configuring NuGet sources..." -ForegroundColor Yellow
        $nugetSources = & dotnet nuget list source 2>&1

        if ($nugetSources -match 'nuget.org') {
            Write-Host "[setup] ✓ nuget.org source configured" -ForegroundColor Green
        } else {
            Write-Host "[setup] Adding nuget.org source..." -ForegroundColor Yellow
            & dotnet nuget add source https://api.nuget.org/v3/index.json --name nuget.org 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[setup] ✓ nuget.org source added" -ForegroundColor Green
            } else {
                Write-Host "[setup] ! Failed to add nuget.org source" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[setup] ✗ .NET SDK not found" -ForegroundColor Red
        if (-not $script:AutoInstall) {
            Write-Host "[setup] Install .NET SDK 8 from: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Gray
        }
        exit 1
    }
}

# ============================================================================
# InvokeBuild Module Setup
# ============================================================================
if (-not $SkipInvokeBuild) {
    Write-Host "[setup] Checking InvokeBuild module..." -ForegroundColor Yellow

    $ibModule = Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ibModule) {
        Write-Host "[setup] ✓ InvokeBuild found: version $($ibModule.Version)" -ForegroundColor Green
    } else {
        Write-Host "[setup] InvokeBuild not found - installing..." -ForegroundColor Yellow

        # Use PS 5.1 to install, then copy to PS 7 (same approach as container test)
        $installCmd = {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction SilentlyContinue
            Install-Module -Name InvokeBuild -Scope CurrentUser -Force -Repository PSGallery -SkipPublisherCheck -AllowClobber -Confirm:$false -WarningAction SilentlyContinue
            $m = Get-Module -ListAvailable -Name InvokeBuild | Select-Object -First 1
            $m.ModuleBase
        }

        try {
            $ps5ModulePath = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $installCmd
            if ($LASTEXITCODE -ne 0 -or -not $ps5ModulePath) {
                throw "Installation in PowerShell 5.1 failed (exit code: $LASTEXITCODE)"
            }

            # Copy to PowerShell 7 module path
            $ps7ModulePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Modules\InvokeBuild"
            $ps7ModulesDir = Split-Path $ps7ModulePath -Parent

            if (-not (Test-Path $ps7ModulesDir)) {
                New-Item -Path $ps7ModulesDir -ItemType Directory -Force | Out-Null
            }
            if (Test-Path $ps7ModulePath) {
                Remove-Item -Path $ps7ModulePath -Recurse -Force
            }

            Copy-Item -Path $ps5ModulePath -Destination $ps7ModulePath -Recurse -Force

            # Verify
            $ibModule = Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue
            if (-not $ibModule) {
                throw "Module not found in PowerShell 7 after copy"
            }

            Write-Host "[setup] ✓ InvokeBuild installed: version $($ibModule.Version)" -ForegroundColor Green
        }
        catch {
            Write-Host "[setup] ✗ Failed to install InvokeBuild: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "[setup] === Infrastructure Setup Complete ===" -ForegroundColor Green
exit 0
