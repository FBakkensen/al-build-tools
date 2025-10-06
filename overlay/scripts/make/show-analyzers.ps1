#requires -Version 7.2

<#
.SYNOPSIS
    Display comprehensive AL analyzer configuration and status with structured formatting.

.DESCRIPTION
    Shows enabled analyzers, compiler information, and resolved analyzer DLL paths in a
    structured format suitable for both interactive display and automation.

.PARAMETER AppDir
    Directory containing .vscode/settings.json (passed from al.build.ps1)

.PARAMETER TestDir
    Directory containing test app .vscode/settings.json (optional, passed from al.build.ps1)

.NOTES
    This script uses standardized output functions from common.psm1 (Write-BuildHeader,
    Write-BuildMessage) to ensure consistent formatting across all build scripts.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,

    [Parameter(Mandatory = $false)]
    [string]$TestDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

# --- Helper Functions ---
function Get-EnabledAnalyzer {
    param([string]$AppDir)
    $settings = Get-SettingsJsonObject $AppDir
    if ($settings -and ($settings.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settings.'al.codeAnalyzers') {
        return $settings.'al.codeAnalyzers'
    }
    return @()
}

# No custom functions needed - use Get-LatestCompilerInfo from common.psm1

$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make show-analyzers)"
    exit $Exit.Guard
}

$alcPath = $null
$compilerRoot = $null
$compilerVersion = $null
$compilerWarning = $null

try {
    $compilerInfo = Get-LatestCompilerInfo
    if ($compilerInfo) {
        $alcPath = $compilerInfo.AlcPath
        $compilerVersion = $compilerInfo.Version
        $compilerRoot = Split-Path -Parent $alcPath
    }
} catch {
    $compilerWarning = $_.Exception.Message
}

$enabledAnalyzers = Get-EnabledAnalyzer $AppDir
$enabledAnalyzers = @($enabledAnalyzers)

Write-BuildHeader 'Enabled Analyzers Configuration (Main App)'

if ($enabledAnalyzers -and $enabledAnalyzers.Count -gt 0) {
    Write-BuildMessage -Type Success -Message "Count: $($enabledAnalyzers.Count) configured"
    Write-BuildMessage -Type Info -Message "Configured analyzers:"
    $enabledAnalyzers | ForEach-Object { Write-BuildMessage -Type Detail -Message $_ }
} else {
    Write-BuildMessage -Type Warning -Message "Count: 0 configured"
    Write-BuildMessage -Type Warning -Message "No analyzers are currently enabled in .vscode/settings.json"
}

# Test App Analyzers (if available)
$testEnabledAnalyzers = @()
if ($TestDir) {
    $testAppJsonPath = Join-Path $TestDir 'app.json'
    if (Test-Path -LiteralPath $testAppJsonPath) {
        $testEnabledAnalyzers = Get-EnabledAnalyzer $TestDir
        $testEnabledAnalyzers = @($testEnabledAnalyzers)

        Write-BuildHeader 'Enabled Analyzers Configuration (Test App)'

        if ($testEnabledAnalyzers -and $testEnabledAnalyzers.Count -gt 0) {
            Write-BuildMessage -Type Success -Message "Count: $($testEnabledAnalyzers.Count) configured"
            Write-BuildMessage -Type Info -Message "Configured analyzers:"
            $testEnabledAnalyzers | ForEach-Object { Write-BuildMessage -Type Detail -Message $_ }
        } else {
            Write-BuildMessage -Type Detail -Message "Count: 0 configured (using main app analyzer settings)"
        }
    }
}

Write-BuildHeader 'Compiler Status'

if ($alcPath) {
    Write-BuildMessage -Type Success -Message "Status: Ready"
    if ($compilerVersion) {
        Write-BuildMessage -Type Detail -Message "Version: $compilerVersion"
    }
    Write-BuildMessage -Type Detail -Message "Path: $alcPath"
} elseif ($compilerWarning) {
    Write-BuildMessage -Type Error -Message $compilerWarning
} else {
    Write-BuildMessage -Type Error -Message "AL compiler context unavailable. Run 'make download-compiler'"
}

$analyzerPaths = Get-EnabledAnalyzerPath -AppDir $AppDir -EnabledAnalyzers $enabledAnalyzers -CompilerDir $compilerRoot
$analyzerPaths = @($analyzerPaths)

Write-BuildHeader 'Analyzer DLL Resolution (Main App)'

if ($analyzerPaths -and $analyzerPaths.Count -gt 0) {
    Write-BuildMessage -Type Success -Message "Found: $($analyzerPaths.Count) DLL files"
    Write-BuildMessage -Type Info -Message "Resolved DLL paths:"
    $analyzerPaths | ForEach-Object {
        $fileName = Split-Path $_ -Leaf
        $dirPath = Split-Path $_ -Parent
        Write-BuildMessage -Type Detail -Message $fileName
        Write-BuildMessage -Type Detail -Message "  $dirPath"
    }
} else {
    Write-BuildMessage -Type Warning -Message "Found: 0 DLL files"
    if ($enabledAnalyzers.Count -gt 0) {
        Write-BuildMessage -Type Error -Message "Analyzer DLLs not found. Run 'make download-compiler' so the compiler's Analyzers folder is available or update settings.json entries"
    } else {
        Write-BuildMessage -Type Warning -Message "No analyzer DLLs found because no analyzers are configured"
    }
}

# Test App DLL Resolution (if test app has analyzers configured)
$testAnalyzerPaths = @()
if ($testEnabledAnalyzers -and $testEnabledAnalyzers.Count -gt 0) {
    $testAnalyzerPaths = Get-EnabledAnalyzerPath -AppDir $TestDir -EnabledAnalyzers $testEnabledAnalyzers -CompilerDir $compilerRoot
    $testAnalyzerPaths = @($testAnalyzerPaths)

    Write-BuildHeader 'Analyzer DLL Resolution (Test App)'

    if ($testAnalyzerPaths -and $testAnalyzerPaths.Count -gt 0) {
        Write-BuildMessage -Type Success -Message "Found: $($testAnalyzerPaths.Count) DLL files"
        Write-BuildMessage -Type Info -Message "Resolved DLL paths:"
        $testAnalyzerPaths | ForEach-Object {
            $fileName = Split-Path $_ -Leaf
            $dirPath = Split-Path $_ -Parent
            Write-BuildMessage -Type Detail -Message $fileName
            Write-BuildMessage -Type Detail -Message "  $dirPath"
        }
    } else {
        Write-BuildMessage -Type Warning -Message "Found: 0 DLL files"
        Write-BuildMessage -Type Error -Message "Test app analyzer DLLs not found. Check settings.json configuration"
    }
}

Write-BuildHeader 'Summary'

$totalEnabled = $enabledAnalyzers.Count + $testEnabledAnalyzers.Count
$totalResolved = $analyzerPaths.Count + $testAnalyzerPaths.Count
$missingCount = [Math]::Max(0, $totalEnabled - $totalResolved)

Write-BuildMessage -Type Detail -Message "Main App - Configured: $($enabledAnalyzers.Count) analyzers, Resolved: $($analyzerPaths.Count) DLL files"
if ($testEnabledAnalyzers.Count -gt 0) {
    Write-BuildMessage -Type Detail -Message "Test App - Configured: $($testEnabledAnalyzers.Count) analyzers, Resolved: $($testAnalyzerPaths.Count) DLL files"
}
Write-BuildMessage -Type Detail -Message "Total - Configured: $totalEnabled analyzers, Resolved: $totalResolved DLL files"
if ($missingCount -gt 0) {
    Write-BuildMessage -Type Detail -Message "Missing: $missingCount DLL files"
}

Write-Host ""
if ($totalResolved -eq $totalEnabled -and $totalEnabled -gt 0) {
    Write-BuildMessage -Type Success -Message "All configured analyzers resolved successfully!"
} elseif ($totalEnabled -eq 0) {
    Write-BuildMessage -Type Warning -Message "No analyzers configured. Consider enabling CodeCop, UICop, or other analyzers in .vscode/settings.json"
} else {
    Write-BuildMessage -Type Warning -Message "Some analyzers could not be resolved. Check compiler installation and settings.json configuration"
}

exit $Exit.Success
