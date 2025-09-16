#requires -Version 7.0

param(
    [string] $Path = 'tests',
    [switch] $CI,
    [switch] $WriteResults,
    [ValidateSet('NUnitXml','JUnitXml')] [string] $ResultsFormat = 'NUnitXml',
    [string] $ResultsFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-TempWorkDir {
    $base = [IO.Path]::GetTempPath()
    $dir  = Join-Path $base ("albt-pester-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# Resolve repo root relative to this script
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
$testsPath = Resolve-Path (Join-Path $repoRootPath $Path)

# Ensure installer helper modules under tests/_install are discoverable
$installHelperPath = Join-Path $testsPath.Path '_install'
$originalPSModulePath = $env:PSModulePath
$psModulePathChanged = $false

if (Test-Path -LiteralPath $installHelperPath) {
    $resolvedInstallHelperPath = (Resolve-Path -LiteralPath $installHelperPath).Path
    $pathSeparator = [IO.Path]::PathSeparator
    $currentModulePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:PSModulePath)) {
        $currentModulePaths = $env:PSModulePath.Split($pathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    if (-not ($currentModulePaths | Where-Object { $_ -ieq $resolvedInstallHelperPath })) {
        if ([string]::IsNullOrWhiteSpace($env:PSModulePath)) {
            $env:PSModulePath = $resolvedInstallHelperPath
        } else {
            $env:PSModulePath = $resolvedInstallHelperPath + $pathSeparator + $env:PSModulePath
        }
        $psModulePathChanged = $true
    }
}


# Ensure repo root stays clean: remove any stray previous results file
$repoResultsPath = Join-Path $repoRootPath 'testResults.xml'
if (Test-Path -LiteralPath $repoResultsPath) {
    try { Remove-Item -LiteralPath $repoResultsPath -Force -ErrorAction SilentlyContinue } catch {}
}

# Decide where to place any optional test results file
$resultsPath = $null
if ($CI -or $WriteResults) {
    $targetDir = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
    if ($ResultsFile) {
        if ([IO.Path]::IsPathRooted($ResultsFile)) { $resultsPath = $ResultsFile }
        else { $resultsPath = Join-Path $targetDir $ResultsFile }
    } else {
        $resultsPath = Join-Path $targetDir 'testResults.xml'
    }
}

# Build Pester 5 configuration
Import-Module Pester -MinimumVersion 5.5.0 -Force
$config = New-PesterConfiguration
$config.Run.Path        = $testsPath.Path
$config.Run.PassThru    = $true
$config.Output.Verbosity = 'Detailed'
$config.Run.Container   = $null

# Disable writing test result files by default; use temp if requested
$config.TestResult.Enabled = $false
if ($resultsPath) {
    $config.TestResult.Enabled     = $true
    $config.TestResult.OutputPath  = $resultsPath
    $config.TestResult.OutputFormat = $ResultsFormat
}

# Run from a temporary working directory so no artifacts land in the repo
$work = New-TempWorkDir
try {
    Push-Location $work
    $res = Invoke-Pester -Configuration $config
} finally {
    Pop-Location
    if ($psModulePathChanged) {
        if ($null -eq $originalPSModulePath) {
            Remove-Item Env:PSModulePath -ErrorAction SilentlyContinue
        } else {
            $env:PSModulePath = $originalPSModulePath
        }
    }
    # Best-effort cleanup of the temp working dir
    try { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue } catch {}
}

if ($CI) {
    if ($res.FailedCount -gt 0) { exit 1 } else { exit 0 }
} else {
    # Print where results were written if requested
    if ($resultsPath) { Write-Host "Test results: $resultsPath" }
}

# Final safety: ensure no testResults.xml was created in repo root by external tools
if (Test-Path -LiteralPath $repoResultsPath) {
    try { Remove-Item -LiteralPath $repoResultsPath -Force -ErrorAction SilentlyContinue } catch {}
}




