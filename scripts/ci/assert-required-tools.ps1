#requires -Version 7.0

<#
.SYNOPSIS
Asserts the presence of required PowerShell tooling modules.

.DESCRIPTION
Checks that each named module is available via Get-Module -ListAvailable.
If any are missing, prints a concise summary and exits with code 6
(standardized MissingTool exit code).

.PARAMETER Modules
Names of modules to verify (e.g., PSScriptAnalyzer, Pester).

.EXAMPLE
./scripts/ci/assert-required-tools.ps1 -Modules PSScriptAnalyzer

.EXAMPLE
./scripts/ci/assert-required-tools.ps1 -Modules Pester
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$Modules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Modules -or $Modules.Count -eq 0) {
    Write-Error 'No modules specified to verify.'
    exit 6
}

$missing = @()
foreach ($name in $Modules) {
    $available = Get-Module -ListAvailable -Name $name -ErrorAction SilentlyContinue
    if (-not $available) {
        $missing += $name
    }
}

if ($missing.Count -gt 0) {
    Write-Host 'Required tools missing:' -ForegroundColor Red
    foreach ($m in $missing) { Write-Host " - $m" -ForegroundColor Red }
    Write-Host 'Install missing modules, e.g.:' -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host "   Install-Module $m -Scope CurrentUser -Force" -ForegroundColor Yellow }
    # Exit code 6 reserved for MissingTool per contract.
    exit 6
}

Write-Host ("All required tools present: {0}" -f ($Modules -join ', ')) -ForegroundColor Green
